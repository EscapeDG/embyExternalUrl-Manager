use std::collections::HashMap;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone)]
struct CommandResult {
    command: String,
    exit_code: i32,
    stdout: String,
    stderr: String,
}

#[derive(Debug, Clone)]
struct CertificateReport {
    cert_directory: String,
    files_written: Vec<String>,
    backups: Vec<String>,
    certificate_info: String,
    command_result: CommandResult,
}

#[derive(Debug, Clone)]
struct SyncReport {
    source_nginx_directory: String,
    target_nginx_directory: String,
    copied_files: Vec<String>,
    skipped_files: Vec<String>,
    protected_files: Vec<String>,
    backup_files: Vec<String>,
    errors: Vec<String>,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let code = match args.get(1).map(String::as_str) {
        Some("cert-update") => {
            let options = parse_options(&args[2..]);
            let report = update_certificate(&options);
            print_certificate_report(&report);
            if report.command_result.exit_code == 0 {
                0
            } else {
                1
            }
        }
        Some("cert-refresh-pfx") => {
            let options = parse_options(&args[2..]);
            let report = refresh_certificate_pfx(&options);
            print_certificate_report(&report);
            if report.command_result.exit_code == 0 {
                0
            } else {
                1
            }
        }
        Some("upstream-sync") => {
            let options = parse_options(&args[2..]);
            let report = sync_upstream(&options);
            print_sync_report(&report);
            if report.errors.is_empty() { 0 } else { 1 }
        }
        Some("git-pull") => {
            let options = parse_options(&args[2..]);
            let repo = get_option(&options, "repo").unwrap_or_default();
            let result = if repo.is_empty() {
                command_failure("git pull --ff-only", "缺少 --repo 参数")
            } else {
                run_command(
                    "/usr/bin/env",
                    &[
                        "git".to_string(),
                        "-C".to_string(),
                        repo,
                        "pull".to_string(),
                        "--ff-only".to_string(),
                    ],
                    None,
                )
            };
            print_command_result(&result);
            if result.exit_code == 0 { 0 } else { 1 }
        }
        Some("git-sync") => {
            let options = parse_options(&args[2..]);
            let repo_url = get_option(&options, "url").unwrap_or_default();
            let repo_dir = get_option(&options, "dir").unwrap_or_default();
            let result = sync_git_repository(&repo_url, &repo_dir);
            print_command_result(&result);
            if result.exit_code == 0 { 0 } else { 1 }
        }
        Some("--version") | Some("-V") => {
            println!("plex2alist-core 1.1.1");
            0
        }
        _ => {
            let result = command_failure(
                "plex2alist-core",
                "用法：plex2alist-core cert-update|cert-refresh-pfx|upstream-sync|git-pull|git-sync",
            );
            print_command_result(&result);
            2
        }
    };
    std::process::exit(code);
}

fn parse_options(args: &[String]) -> HashMap<String, String> {
    let mut options = HashMap::new();
    let mut index = 0;
    while index < args.len() {
        let key = &args[index];
        if let Some(stripped) = key.strip_prefix("--") {
            if let Some(value) = args.get(index + 1) {
                if !value.starts_with("--") {
                    options.insert(stripped.to_string(), value.to_string());
                    index += 2;
                    continue;
                }
            }
            options.insert(stripped.to_string(), String::new());
        }
        index += 1;
    }
    options
}

/// 敏感值优先从环境变量读取（不会出现在进程列表里）；兼容旧的命令行参数写法。
fn option_or_env(options: &HashMap<String, String>, key: &str, env_key: &str) -> String {
    env::var(env_key)
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| get_option(options, key))
        .unwrap_or_default()
}

fn get_option(options: &HashMap<String, String>, key: &str) -> Option<String> {
    options.get(key).map(|value| value.trim().to_string())
}

fn sync_git_repository(repo_url: &str, repo_dir: &str) -> CommandResult {
    if repo_url.trim().is_empty() {
        return command_failure("git-sync", "缺少 --url 参数");
    }
    if repo_dir.trim().is_empty() {
        return command_failure("git-sync", "缺少 --dir 参数");
    }

    let dir = PathBuf::from(repo_dir);
    if dir.join(".git").is_dir() {
        return run_command(
            "/usr/bin/env",
            &[
                "git".to_string(),
                "-C".to_string(),
                repo_dir.to_string(),
                "pull".to_string(),
                "--ff-only".to_string(),
            ],
            None,
        );
    }

    if dir.exists() {
        return command_failure(
            "git clone",
            format!("目标目录已存在但不是 Git 仓库：{}", dir.display()),
        );
    }

    if let Some(parent) = dir.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return command_failure("git clone", format!("无法创建上游缓存目录：{error}"));
        }
    }

    run_command(
        "/usr/bin/env",
        &[
            "git".to_string(),
            "clone".to_string(),
            "--depth".to_string(),
            "1".to_string(),
            repo_url.to_string(),
            repo_dir.to_string(),
        ],
        None,
    )
}

fn update_certificate(options: &HashMap<String, String>) -> CertificateReport {
    let cert_path = get_option(options, "cert").unwrap_or_default();
    let key_path = get_option(options, "key").unwrap_or_default();
    let cert_directory = get_option(options, "dir").unwrap_or_default();
    let pfx_password = option_or_env(options, "pfx-password", "P2A_PFX_PASSWORD");
    let private_key_password = option_or_env(options, "key-password", "P2A_KEY_PASSWORD");

    if cert_path.is_empty() {
        return certificate_failure(cert_directory, "缺少证书 PEM 路径");
    }
    if key_path.is_empty() {
        return certificate_failure(cert_directory, "缺少私钥 PEM 路径");
    }
    if cert_directory.is_empty() {
        return certificate_failure(cert_directory, "缺少证书目录");
    }

    let cert_source = PathBuf::from(&cert_path);
    let key_source = PathBuf::from(&key_path);
    let target_dir = PathBuf::from(&cert_directory);

    if !cert_source.is_file() {
        return certificate_failure(
            cert_directory,
            format!("证书文件不存在：{}", cert_source.display()),
        );
    }
    if !key_source.is_file() {
        return certificate_failure(
            cert_directory,
            format!("私钥文件不存在：{}", key_source.display()),
        );
    }

    let mut files_written = Vec::new();
    let mut backups = Vec::new();

    if let Err(error) = fs::create_dir_all(&target_dir) {
        return certificate_failure(cert_directory, format!("无法创建证书目录：{error}"));
    }

    let cert_pem = target_dir.join("cert.pem");
    let fullchain_pem = target_dir.join("fullchain.pem");
    let key_pem = target_dir.join("key.pem");
    let privkey_pem = target_dir.join("privkey.key");
    let pfx = target_dir.join("certificate.pfx");

    for (source, destination) in [
        (&cert_source, &cert_pem),
        (&cert_source, &fullchain_pem),
        (&key_source, &key_pem),
        (&key_source, &privkey_pem),
    ] {
        match copy_replacing(source, destination, &mut backups) {
            Ok(true) => files_written.push(path_string(destination)),
            Ok(false) => {}
            Err(error) => {
                return certificate_failure(
                    cert_directory,
                    format!("写入 {} 失败：{error}", destination.display()),
                )
            }
        }
    }

    if pfx.exists() {
        match backup_existing_file(&pfx) {
            Ok(backup) => backups.push(path_string(&backup)),
            Err(error) => {
                return certificate_failure(
                    cert_directory,
                    format!("备份旧 PFX 失败：{error}"),
                )
            }
        }
        if let Err(error) = fs::remove_file(&pfx) {
            return certificate_failure(cert_directory, format!("删除旧 PFX 失败：{error}"));
        }
    }

    let mut openssl_args = vec![
        "pkcs12".to_string(),
        "-export".to_string(),
        "-out".to_string(),
        path_string(&pfx),
        "-inkey".to_string(),
        path_string(&key_pem),
        "-in".to_string(),
        path_string(&cert_pem),
        "-passout".to_string(),
        "env:P2A_OPENSSL_PFX_PASS".to_string(),
    ];
    let mut secrets = vec![("P2A_OPENSSL_PFX_PASS", pfx_password.as_str())];
    if !private_key_password.is_empty() {
        openssl_args.push("-passin".to_string());
        openssl_args.push("env:P2A_OPENSSL_KEY_PASS".to_string());
        secrets.push(("P2A_OPENSSL_KEY_PASS", private_key_password.as_str()));
    }

    let command_result = run_command_env("/usr/bin/openssl", &openssl_args, None, &secrets);
    if command_result.exit_code == 0 {
        files_written.push(path_string(&pfx));
    }

    let cert_info = run_command(
        "/usr/bin/openssl",
        &[
            "x509".to_string(),
            "-in".to_string(),
            path_string(&cert_pem),
            "-noout".to_string(),
            "-subject".to_string(),
            "-issuer".to_string(),
            "-dates".to_string(),
        ],
        None,
    );
    let certificate_info = if cert_info.stdout.trim().is_empty() {
        cert_info.stderr
    } else {
        cert_info.stdout
    };

    CertificateReport {
        cert_directory,
        files_written,
        backups,
        certificate_info,
        command_result,
    }
}

fn refresh_certificate_pfx(options: &HashMap<String, String>) -> CertificateReport {
    let cert_directory = get_option(options, "dir").unwrap_or_default();
    let pfx_password = option_or_env(options, "pfx-password", "P2A_PFX_PASSWORD");

    if cert_directory.is_empty() {
        return certificate_failure(cert_directory, "缺少证书目录");
    }

    let target_dir = PathBuf::from(&cert_directory);
    let cert_pem = target_dir.join("cert.pem");
    let fullchain_pem = target_dir.join("fullchain.pem");
    let key_pem = target_dir.join("key.pem");
    let privkey_pem = target_dir.join("privkey.key");
    let pfx = target_dir.join("certificate.pfx");

    if !fullchain_pem.is_file() {
        return certificate_failure(
            cert_directory,
            format!("fullchain.pem 不存在：{}", fullchain_pem.display()),
        );
    }
    if !key_pem.is_file() {
        return certificate_failure(cert_directory, format!("key.pem 不存在：{}", key_pem.display()));
    }

    let mut files_written = Vec::new();
    let mut backups = Vec::new();

    if !cert_pem.is_file() {
        match copy_replacing(&fullchain_pem, &cert_pem, &mut backups) {
            Ok(true) => files_written.push(path_string(&cert_pem)),
            Ok(false) => {}
            Err(error) => {
                return certificate_failure(
                    cert_directory,
                    format!("补齐 cert.pem 失败：{error}"),
                )
            }
        }
    }

    match copy_replacing(&key_pem, &privkey_pem, &mut backups) {
        Ok(true) => files_written.push(path_string(&privkey_pem)),
        Ok(false) => {}
        Err(error) => {
            return certificate_failure(
                cert_directory,
                format!("补齐 privkey.key 失败：{error}"),
            )
        }
    }

    if pfx.exists() {
        match backup_existing_file(&pfx) {
            Ok(backup) => backups.push(path_string(&backup)),
            Err(error) => return certificate_failure(cert_directory, format!("备份旧 PFX 失败：{error}")),
        }
        if let Err(error) = fs::remove_file(&pfx) {
            return certificate_failure(cert_directory, format!("删除旧 PFX 失败：{error}"));
        }
    }

    let openssl_args = vec![
        "pkcs12".to_string(),
        "-export".to_string(),
        "-out".to_string(),
        path_string(&pfx),
        "-inkey".to_string(),
        path_string(&key_pem),
        "-in".to_string(),
        path_string(&fullchain_pem),
        "-passout".to_string(),
        "env:P2A_OPENSSL_PFX_PASS".to_string(),
    ];
    let command_result = run_command_env(
        "/usr/bin/openssl",
        &openssl_args,
        None,
        &[("P2A_OPENSSL_PFX_PASS", pfx_password.as_str())],
    );
    if command_result.exit_code == 0 {
        files_written.push(path_string(&pfx));
    }

    let cert_info = run_command(
        "/usr/bin/openssl",
        &[
            "x509".to_string(),
            "-in".to_string(),
            path_string(&fullchain_pem),
            "-noout".to_string(),
            "-subject".to_string(),
            "-issuer".to_string(),
            "-dates".to_string(),
        ],
        None,
    );
    let certificate_info = if cert_info.stdout.trim().is_empty() {
        cert_info.stderr
    } else {
        cert_info.stdout
    };

    CertificateReport {
        cert_directory,
        files_written,
        backups,
        certificate_info,
        command_result,
    }
}

fn certificate_failure<S: Into<String>, M: Into<String>>(
    cert_directory: S,
    message: M,
) -> CertificateReport {
    CertificateReport {
        cert_directory: cert_directory.into(),
        files_written: Vec::new(),
        backups: Vec::new(),
        certificate_info: String::new(),
        command_result: command_failure("cert-update", message),
    }
}

fn sync_upstream(options: &HashMap<String, String>) -> SyncReport {
    let source_directory = get_option(options, "source").unwrap_or_default();
    let target_nginx_directory = get_option(options, "target").unwrap_or_default();
    let server_type = normalize_server_type(&get_option(options, "server-type").unwrap_or_default());

    if source_directory.is_empty() {
        return sync_failure("", target_nginx_directory, "缺少上游目录");
    }
    if target_nginx_directory.is_empty() {
        return sync_failure("", target_nginx_directory, "缺少目标 nginx 目录");
    }

    let Some(source_nginx) = resolve_source_nginx_directory(Path::new(&source_directory)) else {
        return sync_failure(
            "",
            target_nginx_directory,
            "未找到上游 nginx 目录。请选择包含 plex2Alist/nginx 或 emby2Alist/nginx 的仓库目录，或直接选择 nginx 目录。",
        );
    };

    let target_root = PathBuf::from(&target_nginx_directory);
    if let Err(error) = fs::create_dir_all(&target_root) {
        return sync_failure(
            path_string(&source_nginx),
            target_nginx_directory,
            format!("无法创建目标 nginx 目录：{error}"),
        );
    }

    // 目标目录里现有骨架属于哪种媒体服务器；类型切换时，不能继续保护旧类型的上游文件。
    let previous_type = detect_skeleton_type(&target_root);
    let switching = matches!((&previous_type, &server_type), (Some(old), Some(new)) if old != new);

    let mut files = Vec::new();
    if let Err(error) = walk_regular_files(&source_nginx, &mut files) {
        return sync_failure(
            path_string(&source_nginx),
            target_nginx_directory,
            format!("无法读取上游 nginx 目录：{error}"),
        );
    }

    let mut copied_files = Vec::new();
    let mut skipped_files = Vec::new();
    let mut protected_files = Vec::new();
    let mut backup_files = Vec::new();
    let mut errors = Vec::new();

    for file in files {
        let relative = relative_slash_path(&source_nginx, &file);
        let destination = target_root.join(relative.replace('/', std::path::MAIN_SEPARATOR_STR));

        if is_protected(&relative)
            && destination.exists()
            && !(switching && !is_manager_generated(&relative, server_type.as_deref()))
        {
            protected_files.push(relative);
            continue;
        }

        if let Some(parent) = destination.parent() {
            if let Err(error) = fs::create_dir_all(parent) {
                errors.push(format!("{relative}: 无法创建目录：{error}"));
                continue;
            }
        }

        if destination.exists() {
            match files_equal(&file, &destination) {
                Ok(true) => {
                    skipped_files.push(relative);
                    continue;
                }
                Ok(false) => {}
                Err(error) => {
                    errors.push(format!("{relative}: 无法比较文件：{error}"));
                    continue;
                }
            }

            match backup_existing_file_under_root(&destination, &target_root) {
                Ok(backup) => backup_files.push(path_string(&backup)),
                Err(error) => {
                    errors.push(format!("{relative}: 备份失败：{error}"));
                    continue;
                }
            }

            if let Err(error) = fs::remove_file(&destination) {
                errors.push(format!("{relative}: 删除旧文件失败：{error}"));
                continue;
            }
        }

        match fs::copy(&file, &destination) {
            Ok(_) => copied_files.push(relative),
            Err(error) => errors.push(format!("{relative}: 复制失败：{error}")),
        }
    }

    prune_oldest(&target_root.join(".manager-backups").join("upstream-sync"), MAX_BACKUPS, |_| true);

    if errors.is_empty() {
        if let Some(kind) = &server_type {
            if let Err(error) = fs::write(target_root.join(SKELETON_MARKER), format!("{kind}\n")) {
                errors.push(format!("{SKELETON_MARKER}: 无法写入骨架类型标记：{error}"));
            }
        }
    }

    copied_files.sort();
    skipped_files.sort();
    protected_files.sort();
    backup_files.sort();
    errors.sort();

    SyncReport {
        source_nginx_directory: path_string(&source_nginx),
        target_nginx_directory,
        copied_files,
        skipped_files,
        protected_files,
        backup_files,
        errors,
    }
}

fn sync_failure<S: Into<String>, T: Into<String>, M: Into<String>>(
    source_nginx_directory: S,
    target_nginx_directory: T,
    message: M,
) -> SyncReport {
    SyncReport {
        source_nginx_directory: source_nginx_directory.into(),
        target_nginx_directory: target_nginx_directory.into(),
        copied_files: Vec::new(),
        skipped_files: Vec::new(),
        protected_files: Vec::new(),
        backup_files: Vec::new(),
        errors: vec![message.into()],
    }
}

fn resolve_source_nginx_directory(source: &Path) -> Option<PathBuf> {
    [
        source.join("plex2Alist").join("nginx"),
        source.join("emby2Alist").join("nginx"),
        source.join("nginx"),
        source.to_path_buf(),
    ]
    .into_iter()
    .find(|candidate| candidate.join("nginx.conf").is_file() && candidate.join("conf.d").is_dir())
}

fn walk_regular_files(root: &Path, files: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let file_name = entry.file_name();
        if file_name.to_string_lossy().starts_with('.') {
            continue;
        }
        let file_type = entry.file_type()?;
        let path = entry.path();
        if file_type.is_dir() {
            walk_regular_files(&path, files)?;
        } else if file_type.is_file() {
            files.push(path);
        }
    }
    Ok(())
}

fn is_protected(relative_path: &str) -> bool {
    relative_path == "conf.d/constant.js"
        || relative_path.starts_with("conf.d/cert/")
        || (relative_path.starts_with("conf.d/includes/") && relative_path.ends_with(".conf"))
        || (relative_path.starts_with("conf.d/config/constant") && relative_path.ends_with(".js"))
}

/// 每个文件 / 每次同步最多保留的备份数量。
const MAX_BACKUPS: usize = 5;

/// 只保留 `dir` 下排序最靠后（最新）的 `keep` 个条目；时间戳在名称里，按名称排序即按时间。
fn prune_oldest(dir: &Path, keep: usize, matches: impl Fn(&str) -> bool) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut names: Vec<String> = entries
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| matches(name))
        .collect();
    names.sort();
    if names.len() > keep {
        for name in &names[..names.len() - keep] {
            let path = dir.join(name);
            let _ = if path.is_dir() { fs::remove_dir_all(&path) } else { fs::remove_file(&path) };
        }
    }
}

const SKELETON_MARKER: &str = ".manager-skeleton-type";

/// 把 plex / emby / jellyfin 归一为骨架类型：plex 或 emby（jellyfin 复用 emby2Alist 骨架）。
fn normalize_server_type(value: &str) -> Option<String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "plex" => Some("plex".to_string()),
        "emby" | "jellyfin" => Some("emby".to_string()),
        _ => None,
    }
}

/// 判断目标目录现有骨架属于 plex 还是 emby：优先读标记文件，其次从 constant.js / plex.js / emby.js 推断。
fn detect_skeleton_type(target_root: &Path) -> Option<String> {
    if let Ok(text) = fs::read_to_string(target_root.join(SKELETON_MARKER)) {
        if let Some(kind) = normalize_server_type(&text) {
            return Some(kind);
        }
    }
    let conf_d = target_root.join("conf.d");
    if let Ok(text) = fs::read_to_string(conf_d.join("constant.js")) {
        if text.contains("plexHost") {
            return Some("plex".to_string());
        }
        if text.contains("embyHost") {
            return Some("emby".to_string());
        }
    }
    let has_plex = conf_d.join("plex.js").is_file();
    let has_emby = conf_d.join("emby.js").is_file();
    match (has_plex, has_emby) {
        (true, false) => Some("plex".to_string()),
        (false, true) => Some("emby".to_string()),
        _ => None,
    }
}

/// 由 Manager 「生成」步骤写入的文件；类型切换后仍保护，等待重新生成覆盖。
/// 其余受保护文件（constant-common / strm / symlink / nginx、proxy-header.conf 等）属于上游骨架，
/// 两种骨架内容不同，类型切换时必须替换（同步前会备份）。
fn is_manager_generated(relative_path: &str, server_type: Option<&str>) -> bool {
    matches!(
        relative_path,
        "conf.d/constant.js"
            | "conf.d/config/constant-mount.js"
            | "conf.d/config/constant-pro.js"
            | "conf.d/config/constant-transcode.js"
            | "conf.d/includes/http.conf"
            | "conf.d/includes/https.conf"
    ) || relative_path.starts_with("conf.d/cert/")
        || (relative_path == "conf.d/config/constant-ext.js" && server_type == Some("emby"))
}

fn copy_replacing(source: &Path, destination: &Path, backups: &mut Vec<String>) -> io::Result<bool> {
    if same_existing_file(source, destination) {
        return Ok(false);
    }
    if destination.exists() {
        let backup = backup_existing_file(destination)?;
        backups.push(path_string(&backup));
        fs::remove_file(destination)?;
    }
    fs::copy(source, destination)?;
    Ok(true)
}

fn same_existing_file(source: &Path, destination: &Path) -> bool {
    match (fs::canonicalize(source), fs::canonicalize(destination)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

fn backup_existing_file(path: &Path) -> io::Result<PathBuf> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let file_name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "backup".to_string());
    let backup = parent.join(format!("{file_name}.{}.bak", timestamp()));
    fs::copy(path, &backup)?;
    let prefix = format!("{file_name}.");
    prune_oldest(parent, MAX_BACKUPS, |name| name.starts_with(&prefix) && name.ends_with(".bak"));
    Ok(backup)
}

fn backup_existing_file_under_root(path: &Path, target_root: &Path) -> io::Result<PathBuf> {
    let relative = path.strip_prefix(target_root).unwrap_or(path);
    let backup = target_root
        .join(".manager-backups")
        .join("upstream-sync")
        .join(timestamp())
        .join(relative);
    if let Some(parent) = backup.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(path, &backup)?;
    Ok(backup)
}

fn files_equal(left: &Path, right: &Path) -> io::Result<bool> {
    Ok(fs::read(left)? == fs::read(right)?)
}

fn run_command(program: &str, args: &[String], visible_args: Option<&[String]>) -> CommandResult {
    run_command_env(program, args, visible_args, &[])
}

fn run_command_env(
    program: &str,
    args: &[String],
    visible_args: Option<&[String]>,
    envs: &[(&str, &str)],
) -> CommandResult {
    let output = Command::new(program).args(args).envs(envs.iter().copied()).output();
    let display_args = visible_args.unwrap_or(args);
    match output {
        Ok(output) => CommandResult {
            command: command_line(program, display_args),
            exit_code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        },
        Err(error) => CommandResult {
            command: command_line(program, display_args),
            exit_code: -1,
            stdout: String::new(),
            stderr: error.to_string(),
        },
    }
}

fn command_failure<C: Into<String>, M: Into<String>>(command: C, message: M) -> CommandResult {
    CommandResult {
        command: command.into(),
        exit_code: -1,
        stdout: String::new(),
        stderr: message.into(),
    }
}

fn command_line(program: &str, args: &[String]) -> String {
    std::iter::once(program.to_string())
        .chain(args.iter().cloned())
        .map(|token| display_token(&token))
        .collect::<Vec<_>>()
        .join(" ")
}

fn display_token(token: &str) -> String {
    if token
        .chars()
        .any(|char| char.is_whitespace() || matches!(char, '\'' | '"' | '\\'))
    {
        format!("'{}'", token.replace('\'', "'\\''"))
    } else {
        token.to_string()
    }
}

fn timestamp() -> String {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format!("{:012}-{:09}", duration.as_secs(), duration.subsec_nanos())
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn relative_slash_path(root: &Path, path: &Path) -> String {
    let relative = path.strip_prefix(root).unwrap_or(path);
    relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/")
}

fn print_certificate_report(report: &CertificateReport) {
    println!(
        "{{\"certDirectory\":{},\"filesWritten\":{},\"backups\":{},\"certificateInfo\":{},\"commandResult\":{}}}",
        json_string(&report.cert_directory),
        json_array(&report.files_written),
        json_array(&report.backups),
        json_string(&report.certificate_info),
        command_result_json(&report.command_result)
    );
}

fn print_sync_report(report: &SyncReport) {
    println!(
        "{{\"sourceNginxDirectory\":{},\"targetNginxDirectory\":{},\"copiedFiles\":{},\"skippedFiles\":{},\"protectedFiles\":{},\"backupFiles\":{},\"errors\":{}}}",
        json_string(&report.source_nginx_directory),
        json_string(&report.target_nginx_directory),
        json_array(&report.copied_files),
        json_array(&report.skipped_files),
        json_array(&report.protected_files),
        json_array(&report.backup_files),
        json_array(&report.errors)
    );
}

fn print_command_result(result: &CommandResult) {
    println!("{}", command_result_json(result));
}

fn command_result_json(result: &CommandResult) -> String {
    format!(
        "{{\"command\":{},\"exitCode\":{},\"stdout\":{},\"stderr\":{}}}",
        json_string(&result.command),
        result.exit_code,
        json_string(&result.stdout),
        json_string(&result.stderr)
    )
}

fn json_array(items: &[String]) -> String {
    format!(
        "[{}]",
        items
            .iter()
            .map(|item| json_string(item))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn json_string(value: &str) -> String {
    let mut output = String::with_capacity(value.len() + 2);
    output.push('"');
    for char in value.chars() {
        match char {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            '\u{08}' => output.push_str("\\b"),
            '\u{0c}' => output.push_str("\\f"),
            char if char <= '\u{1f}' => output.push_str(&format!("\\u{:04x}", char as u32)),
            char => output.push(char),
        }
    }
    output.push('"');
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protected_paths_match_generated_parameters() {
        assert!(is_protected("conf.d/constant.js"));
        assert!(is_protected("conf.d/config/constant-pro.js"));
        assert!(is_protected("conf.d/config/constant-transcode.js"));
        assert!(is_protected("conf.d/includes/http.conf"));
        assert!(is_protected("conf.d/cert/cert.pem"));
        assert!(!is_protected("nginx.conf"));
        assert!(!is_protected("conf.d/example.js"));
    }

    #[test]
    fn type_switch_replaces_upstream_files_but_keeps_generated_ones() {
        let base = std::env::temp_dir().join(format!("p2a-test-{}", timestamp()));
        let source = base.join("src/nginx");
        let target = base.join("dst");
        for (root, tag) in [(&source, "emby-upstream"), (&target, "plex-old")] {
            fs::create_dir_all(root.join("conf.d/config")).unwrap();
            fs::write(root.join("nginx.conf"), "x").unwrap();
            fs::write(root.join("conf.d/config/constant-common.js"), tag).unwrap();
            fs::write(root.join("conf.d/config/constant-pro.js"), tag).unwrap();
        }
        fs::write(target.join("conf.d/plex.js"), "p").unwrap();

        let mut options = HashMap::new();
        options.insert("source".to_string(), path_string(&source));
        options.insert("target".to_string(), path_string(&target));
        options.insert("server-type".to_string(), "emby".to_string());
        let report = sync_upstream(&options);
        assert!(report.errors.is_empty(), "{:?}", report.errors);

        // 上游骨架文件被替换，生成文件仍保护
        assert_eq!(fs::read_to_string(target.join("conf.d/config/constant-common.js")).unwrap(), "emby-upstream");
        assert_eq!(fs::read_to_string(target.join("conf.d/config/constant-pro.js")).unwrap(), "plex-old");
        assert_eq!(fs::read_to_string(target.join(SKELETON_MARKER)).unwrap().trim(), "emby");
        assert!(!report.backup_files.is_empty());

        // 同类型再次同步：全部保护
        fs::write(target.join("conf.d/config/constant-common.js"), "user-edit").unwrap();
        let report = sync_upstream(&options);
        assert!(report.protected_files.contains(&"conf.d/config/constant-common.js".to_string()));
        assert_eq!(fs::read_to_string(target.join("conf.d/config/constant-common.js")).unwrap(), "user-edit");
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn backups_are_pruned_to_the_newest_few() {
        let dir = std::env::temp_dir().join(format!("p2a-prune-{}", timestamp()));
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("cert.pem");
        fs::write(&file, "x").unwrap();
        for _ in 0..(MAX_BACKUPS + 4) {
            backup_existing_file(&file).unwrap();
        }
        let count = fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().ends_with(".bak"))
            .count();
        assert_eq!(count, MAX_BACKUPS);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn pfx_password_is_not_exposed_in_command_line() {
        let dir = std::env::temp_dir().join(format!("p2a-pfx-{}", timestamp()));
        fs::create_dir_all(&dir).unwrap();
        let (cert, key) = (dir.join("c.pem"), dir.join("k.pem"));
        let gen = Command::new("/usr/bin/openssl")
            .args(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=t"])
            .args(["-keyout", &path_string(&key), "-out", &path_string(&cert)])
            .output();
        if gen.map(|o| o.status.success()).unwrap_or(false) {
            let mut options = HashMap::new();
            options.insert("cert".to_string(), path_string(&cert));
            options.insert("key".to_string(), path_string(&key));
            options.insert("dir".to_string(), path_string(&dir.join("out")));
            env::set_var("P2A_PFX_PASSWORD", "s3cret-pass");
            let report = update_certificate(&options);
            env::remove_var("P2A_PFX_PASSWORD");
            assert_eq!(report.command_result.exit_code, 0, "{}", report.command_result.stderr);
            assert!(!report.command_result.command.contains("s3cret-pass"));
            assert!(dir.join("out/certificate.pfx").is_file());
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn json_string_escapes_control_characters() {
        assert_eq!(json_string("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
    }
}

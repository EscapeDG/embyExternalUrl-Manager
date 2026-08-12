import SwiftUI

struct PathMappingView: View {
    @EnvironmentObject var configService: ConfigService

    var body: some View {
        PageScaffold(title: "路径映射", useScroll: false) {
            List {
                Section {
                    Text("\(configService.config.mediaServerType.rawValue) 媒体库的文件挂载根路径。上游会先移除这些前缀，再用剩余路径去 OpenList 查询同名文件。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)

                    ForEach(Array(configService.config.mount.mediaMountPaths.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            TextField("/mnt", text: bindingForMountPath(at: index))
                                .font(.system(.body, design: .monospaced))
                            Button {
                                configService.config.mount.mediaMountPaths.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Button {
                        withAnimation {
                            configService.config.mount.mediaMountPaths.append("")
                        }
                    } label: {
                        Label("添加挂载路径", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Label("挂载根路径", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                }

                Section {
                    Text("可选项。仅当 \(configService.config.mediaServerType.rawValue) 文件路径和 OpenList 路径不一致时使用；路径一致时保持为空即可。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)

                    if configService.config.pathMappings.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("尚未添加路径映射规则。适合两边目录结构一致的场景。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }

                    ForEach($configService.config.pathMappings) { $mapping in
                        ViewThatFits(in: .horizontal) {
                            mappingRowHorizontal($mapping)
                            mappingRowVertical($mapping)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        configService.config.pathMappings.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { indexSet in
                        configService.config.pathMappings.remove(atOffsets: indexSet)
                    }

                    Button {
                        withAnimation {
                            configService.config.pathMappings.append(PathMapping())
                        }
                    } label: {
                        Label("添加映射", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Label("路径映射", systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .padding(.top, 8)
        } footer: {
            ConfigSaveBar()
        }
    }

    private func mappingRowHorizontal(_ mapping: Binding<PathMapping>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: mapping.enabled)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    Text("本地路径前缀")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("/mnt/aliyun", text: mapping.localPrefix)
                        .font(.system(.body, design: .monospaced))
                }
                .frame(minWidth: 160)

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenList 路径前缀")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("/aliyun", text: mapping.remotePrefix)
                        .font(.system(.body, design: .monospaced))
                }
                .frame(minWidth: 160)

                Button {
                    withAnimation {
                        configService.config.pathMappings.removeAll { $0.id == mapping.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("删除此映射")
            }

            TextField("备注（可选）", text: mapping.note)
                .font(.caption)
        }
    }

    private func mappingRowVertical(_ mapping: Binding<PathMapping>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("启用", isOn: mapping.enabled)
                Spacer()
                Button(role: .destructive) {
                    withAnimation {
                        configService.config.pathMappings.removeAll { $0.id == mapping.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            FormField(label: "本地路径前缀") {
                TextField("/mnt/aliyun", text: mapping.localPrefix)
                    .font(.system(.body, design: .monospaced))
            }
            FormField(label: "OpenList 路径前缀") {
                TextField("/aliyun", text: mapping.remotePrefix)
                    .font(.system(.body, design: .monospaced))
            }
            TextField("备注（可选）", text: mapping.note)
                .font(.caption)
        }
    }

    private func bindingForMountPath(at index: Int) -> Binding<String> {
        Binding {
            guard index < configService.config.mount.mediaMountPaths.count else { return "" }
            return configService.config.mount.mediaMountPaths[index]
        } set: { newValue in
            guard index < configService.config.mount.mediaMountPaths.count else { return }
            configService.config.mount.mediaMountPaths[index] = newValue
        }
    }
}

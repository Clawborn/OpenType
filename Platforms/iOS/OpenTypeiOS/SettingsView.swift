import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var tokenDraft = ""
    @State private var tokenMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("界面", "Interface", language: settings.language)) {
                    Picker(L10n.text("语言", "Language", language: settings.language), selection: $settings.language) {
                        Text("中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker(
                        L10n.text("识别语言", "Recognition language", language: settings.language),
                        selection: $settings.speechLocaleIdentifier
                    ) {
                        Text("中文 / 中英混合").tag("zh-CN")
                        Text("English").tag("en-US")
                        Text("日本語").tag("ja-JP")
                    }
                    Toggle(
                        L10n.text("优先使用设备端识别", "Prefer on-device recognition", language: settings.language),
                        isOn: $settings.preferOnDeviceRecognition
                    )
                    Text(L10n.text(
                        "设备或语言不支持时，Apple Speech 会自动使用系统在线识别。原始音频不会保存。",
                        "Apple Speech may use system online recognition when the device or language does not support on-device recognition. Raw audio is never saved.",
                        language: settings.language
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text(L10n.text("语音识别", "Speech Recognition", language: settings.language))
                }

                Section {
                    Picker(
                        L10n.text("供应商", "Provider", language: settings.language),
                        selection: Binding(
                            get: { settings.provider },
                            set: { settings.selectProvider($0) }
                        )
                    ) {
                        ForEach(CloudProvider.allCases) { provider in
                            Text(provider.title(settings.language)).tag(provider)
                        }
                    }
                    TextField(L10n.text("模型", "Model", language: settings.language), text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if settings.provider == .compatible {
                        TextField("https://…/v1/chat/completions", text: $settings.compatibleBaseURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Circle()
                            .fill(settings.tokenIsSaved ? Color.blue : Color.secondary.opacity(0.35))
                            .frame(width: 8, height: 8)
                        Text(settings.tokenIsSaved
                             ? L10n.text("Token 已保存在 Keychain", "Token saved in Keychain", language: settings.language)
                             : L10n.text("尚未保存 Token", "No token saved", language: settings.language))
                            .font(.subheadline)
                    }
                    SecureField(L10n.text("输入新的 API Token", "Enter a new API token", language: settings.language), text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(L10n.text("保存 Token", "Save token", language: settings.language)) { saveToken() }
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if settings.tokenIsSaved {
                            Button(L10n.text("移除已存 Token", "Remove saved token", language: settings.language), role: .destructive) {
                                deleteToken()
                            }
                        }
                    }
                    if !tokenMessage.isEmpty {
                        Text(tokenMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.text("云端文字模型", "Cloud Text Model", language: settings.language))
                } footer: {
                    Text(L10n.text(
                        "Token 只保存在本机 Keychain，不会写入 App Group，也不会分享给键盘扩展。文字转写模式不调用云端文字模型。",
                        "Tokens stay in the local Keychain. They are never written to the App Group or shared with the keyboard. Transcribe mode does not call the cloud text model.",
                        language: settings.language
                    ))
                }

                Section {
                    setupStep("1", L10n.text("打开 设置 → 通用 → 键盘 → 键盘", "Open Settings → General → Keyboard → Keyboards", language: settings.language))
                    setupStep("2", L10n.text("添加新键盘，选择 OpenType", "Add New Keyboard and choose OpenType", language: settings.language))
                    setupStep("3", L10n.text("为 App Group 同步开启“允许完全访问”", "Enable Allow Full Access for App Group sync", language: settings.language))
                    setupStep("4", L10n.text("生成后回到目标 App，切换键盘并一键插入", "After generating, return to the target app, switch keyboards, and insert", language: settings.language))
                    Button(L10n.text("打开 OpenType 系统设置", "Open OpenType Settings", language: settings.language)) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    Text(L10n.text(
                        "App Group 同步需要“允许完全访问”，但键盘仍然不能录音。Token 不会进入 App Group；扩展只读取最近一次生成结果。",
                        "App Group sync requires Allow Full Access, but the keyboard still cannot record. Tokens never enter the App Group; the extension reads only the latest result.",
                        language: settings.language
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text(L10n.text("OpenType 键盘", "OpenType Keyboard", language: settings.language))
                }

                Section(L10n.text("隐私", "Privacy", language: settings.language)) {
                    Label(
                        L10n.text("原始转写、模式、结果和时间仅保存在本机历史", "Original transcript, mode, result, and time stay in local history", language: settings.language),
                        systemImage: "lock"
                    )
                    Label(
                        L10n.text("不会自动发送或发布内容", "Content is never sent or published automatically", language: settings.language),
                        systemImage: "paperplane"
                    )
                }
            }
            .navigationTitle(L10n.text("设置", "Settings", language: settings.language))
            .onAppear { settings.refreshTokenStatus() }
        }
    }

    private func setupStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.bold()).foregroundStyle(.blue)
                .frame(width: 24, height: 24).background(Color.blue.opacity(0.12), in: Circle())
            Text(text).font(.subheadline)
        }
    }

    private func saveToken() {
        do {
            try settings.saveToken(tokenDraft)
            tokenDraft = ""
            tokenMessage = L10n.text("已保存。", "Saved.", language: settings.language)
        } catch {
            tokenMessage = error.localizedDescription
        }
    }

    private func deleteToken() {
        do {
            try settings.deleteToken()
            tokenDraft = ""
            tokenMessage = L10n.text("已移除。", "Removed.", language: settings.language)
        } catch {
            tokenMessage = error.localizedDescription
        }
    }
}

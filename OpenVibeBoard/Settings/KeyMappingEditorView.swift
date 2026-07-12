//
//  KeyMappingEditorView.swift
//  OpenVibeBoard
//
//  单个映射的详情编辑器。
//

import SwiftUI

struct KeyMappingEditorView: View {
    let key: String
    @Binding var mapping: KeyConfig

    var body: some View {
        Form {
            Section("动作") {
                Picker("类型", selection: $mapping.type) {
                    Text("命令").tag("cmd")
                    Text("快捷键").tag("key")
                    Text("文本").tag("text")
                }
                .pickerStyle(.menu)
                .onChange(of: mapping.type) {
                    normalizeConditionalFields()
                }

                valueEditor
            }

            Section("说明") {
                TextField("描述", text: descriptionBinding, prompt: Text("可选"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(key)
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch mapping.type {
        case "key":
            LabeledContent("快捷键") {
                KeyRecorderView(value: $mapping.value)
                    .frame(maxWidth: 320)
            }

            Picker("触发方式", selection: modeBinding) {
                Text("按下一次").tag("tap")
                Text("按住期间").tag("hold")
            }
            .pickerStyle(.segmented)

        case "text":
            TextField("输入文本", text: $mapping.value, prompt: Text("要粘贴的内容"))
            Toggle("粘贴后按下回车", isOn: enterBinding)

        default:
            TextField("命令", text: $mapping.value, prompt: Text("例如 open -a Codex"))
                .fontDesign(.monospaced)
        }
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { mapping.desc ?? "" },
            set: { mapping.desc = $0.isEmpty ? nil : $0 }
        )
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { mapping.mode ?? "tap" },
            set: { mapping.mode = $0 }
        )
    }

    private var enterBinding: Binding<Bool> {
        Binding(
            get: { mapping.enter ?? true },
            set: { mapping.enter = $0 }
        )
    }

    private func normalizeConditionalFields() {
        switch mapping.type {
        case "key":
            mapping.enter = nil
            mapping.mode = mapping.mode ?? "tap"
        case "text":
            mapping.mode = nil
            mapping.enter = mapping.enter ?? true
        default:
            mapping.mode = nil
            mapping.enter = nil
        }
    }
}

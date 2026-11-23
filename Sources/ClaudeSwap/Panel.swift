import AppKit
import ServiceManagement
import SwapCore
import SwiftUI

extension Presentation.Tone {
    var color: Color {
        switch self {
        case .normal: return .secondary
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        case .dim: return Color.secondary.opacity(0.6)
        }
    }
}

struct Panel: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.login != nil {
                LoginView()
                Divider()
            }
            MachineSection(machine: model.local)
            if let remote = model.remote {
                Divider()
                MachineSection(machine: remote)
            }
            Divider()
            Footer()
        }
        .padding(12)
        .frame(width: 400)
        .onAppear { model.opened() }
    }
}

struct MachineSection: View {
    @EnvironmentObject var model: Model
    let machine: Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(machine.title).font(.headline)
                Spacer()
                if let s = machine.snapshot {
                    Text(Presentation.summary(s, now: model.now))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let problem = machine.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let s = machine.snapshot {
                ForEach(s.accounts) { account in
                    AccountRow(account: account, machine: machine)
                }
                .opacity(machine.isRemote && machine.problem != nil ? 0.55 : 1)
                let extra = Presentation.extraUSD(s)
                if extra > 0 {
                    Text(String(format: "Extra usage this month: $%.2f", extra))
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
        }
    }
}

struct AccountRow: View {
    @EnvironmentObject var model: Model
    let account: Account
    let machine: Machine
    @State private var hovering = false

    var body: some View {
        let now = model.now
        let percent = Presentation.sessionPercent(account, now: now)
        let note = Presentation.note(account, now: now)
        let weekly = Presentation.weekly(account, now: now)
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 8)).foregroundStyle(Color.accentColor)
                .opacity(account.active ? 1 : 0)
            Text(account.name)
                .fontWeight(account.active ? .semibold : .regular)
                .foregroundStyle(account.login == .ok ? .primary : .secondary)
                .frame(width: 78, alignment: .leading).lineLimit(1)
            if account.login == .ok {
                UsageBar(percent: percent, tone: Presentation.usageTone(percent))
                    .frame(width: 60, height: 6)
                Text("\(percent)%").monospacedDigit()
                    .foregroundStyle(Presentation.usageTone(percent).color)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Image(systemName: account.login == .loggedOut ? "person.crop.circle.badge.xmark" : "person.crop.circle.dashed")
                    .foregroundStyle(note.tone.color)
                    .frame(width: 106, alignment: .leading)
            }
            Text(note.text).font(.caption).foregroundStyle(note.tone.color).lineLimit(1)
            Spacer(minLength: 0)
            action
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help([account.email, weekly.isEmpty ? nil : "Weekly: \(weekly)",
               account.checkedAt.map { "Checked \(Presentation.ago($0, now: now))" }]
            .compactMap { $0 }.joined(separator: "\n"))
    }

    @ViewBuilder private var action: some View {
        let idle = model.busy == nil && model.login == nil
        if account.login != .ok, machine.loginHelper != nil {
            Button("Log in") { model.startLogin(account, on: machine) }
                .controlSize(.small).disabled(!idle)
        } else if account.login == .ok, !account.active, !machine.isRemote, hovering {
            Button("Use") { model.use(account) }
                .controlSize(.small).disabled(!idle)
        }
    }
}

struct UsageBar: View {
    let percent: Int
    let tone: Presentation.Tone

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tone.color)
                    .frame(width: max(percent > 0 ? 3 : 0, geo.size.width * CGFloat(min(percent, 100)) / 100))
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        if let flow = model.login {
            VStack(alignment: .leading, spacing: 6) {
                Text("Log in \(flow.account.name) on \(flow.isRemote ? (model.remote?.title ?? "the other machine") : "this Mac")")
                    .font(.headline)
                switch flow.phase {
                case .starting:
                    HStack { ProgressView().controlSize(.small); Text("Getting a sign-in link…") }
                case .waitingForCode, .finishing:
                    Text("Sign in as \(flow.account.email) in the browser, approve, then paste the code it shows. If the browser is signed in to another account, copy the link into a private window instead.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Code", text: Binding(get: { model.login?.code ?? "" },
                                                        set: { model.login?.code = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.finishLogin() }
                        if flow.phase == .finishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Finish") { model.finishLogin() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(flow.code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .disabled(flow.phase == .finishing)
                case .failed(let why):
                    Label(why, systemImage: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if let link = flow.link, flow.phase == .waitingForCode {
                        Button("Open Link Again") { NSWorkspace.shared.open(link) }
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.absoluteString, forType: .string)
                        }
                    }
                    if case .failed = flow.phase {
                        Button("Try Again") {
                            if let machine = flow.isRemote ? model.remote : model.local {
                                model.startLogin(flow.account, on: machine)
                            }
                        }
                    }
                    Spacer()
                    Button("Cancel") { model.cancelLogin() }.disabled(flow.phase == .finishing)
                }
                .controlSize(.small)
            }
        }
    }
}

struct Footer: View {
    @EnvironmentObject var model: Model
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let busy = model.busy {
                HStack { ProgressView().controlSize(.small); Text(busy).font(.caption) }
            } else if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Refresh") { model.refresh() }.disabled(model.busy != nil)
                if let s = model.local.snapshot {
                    Text("Updated \(Presentation.ago(s.writtenAt, now: model.now))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        model.notice = "Couldn't change the login item: \(error.localizedDescription)"
                    }
                    opensAtLogin = SMAppService.mainApp.status == .enabled
                }))
                .toggleStyle(.checkbox)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

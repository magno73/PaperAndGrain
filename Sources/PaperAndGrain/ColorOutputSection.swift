import AppKit
import SwiftUI

/// **Book & Print › Color**: sRGB, or CMYK with an output profile. A profile chosen here (bundled, PSO
/// Coated v3 from ECI, installed on the Mac, or a file) is kept as `pending` and copied into the book
/// package only when the author applies the sheet, so Cancel leaves the package untouched.
struct ColorOutputSection: View, Localizing {
    @Binding var output: ColorOutput?
    @Binding var pending: PendingICCProfile?
    /// The book package; nil while the book has no package, when CMYK cannot be chosen.
    let directory: URL?
    /// The color modes the chosen print service accepts, and the profile it names, if any.
    let serviceAccepts: [PrintProfile.ColorMode]?
    let printerProfile: String?
    let language: String

    @State private var problem: String?
    @State private var downloading = false
    @State private var psoInstalled = ECIProfile.installedData() != nil
    @State private var installed: [ICCProfileSources.Installed] = []

    private var cmyk: Binding<Bool> {
        Binding(get: { output?.mode == .cmyk }, set: { on in
            output = on ? ColorOutput(mode: .cmyk, profile: output?.profile) : nil
            if on, output?.profile == nil { preselect() }
        })
    }

    private var candidate: ICCProfileSources.Candidate? {
        printerProfile.flatMap { ICCProfileSources.candidate(for: $0, installed: installed) }
    }

    var body: some View {
        Section(tr("Color")) {
            Picker(tr("Color"), selection: cmyk) {
                Text("sRGB").tag(false)
                Text("CMYK").tag(true)
            }
            .pickerStyle(.segmented)
            .help(tr("CMYK converts the print PDFs to the printer’s profile. The editor and the viewing PDF stay sRGB."))
            .disabled(directory == nil)
            if let accepts = serviceAccepts {
                let writes: PrintProfile.ColorMode = output?.mode == .cmyk ? .cmyk : .srgb
                if !accepts.contains(writes), let asked = accepts.first {
                    Text(asked == .cmyk ? tr("The print service asks for CMYK.") : tr("The print service asks for sRGB."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if output?.mode == .cmyk {
                printerProfileNote
                Menu(output?.profile?.name ?? tr("Choose a Profile")) { profileMenu }
                    .help(tr("The CMYK output profile the printer names."))
                if !psoInstalled {
                    Text(tr("Download PSO Coated v3 from ECI… contacts eci.org once; the profile belongs to ECI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let name = output?.profile?.name {
                    Text(tr("CMYK with %@. Not a certified PDF/X file; check it with your printer’s preflight.", name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if downloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(tr("Downloading PSO Coated v3 from eci.org…")).font(.caption)
                    }
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            installed = await Task.detached { ICCProfileSources.installed() }.value
            if output?.mode == .cmyk, output?.profile == nil { preselect() }
        }
    }

    /// Which profile the printer asks for, and how to get it.
    @ViewBuilder private var printerProfileNote: some View {
        if let printerProfile {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("The printer asks for the profile %@.", printerProfile))
                switch candidate {
                case let .bundled(profile)?:
                    if output?.profile?.id != profile.id, let data = ICCProfileSources.bundledData(profile) {
                        Button(tr("Use %@", ICCProfileInfo(data)?.name ?? profile.filename)) {
                            use(data, named: profile.filename, id: profile.id)
                        }
                    }
                case let .installed(profile)?:
                    if output?.profile?.name != profile.name {
                        Button(tr("Use %@", profile.name)) { useInstalled(profile) }
                    }
                case .eci?:
                    if output?.profile?.id != ECIProfile.id {
                        if psoInstalled, let data = ECIProfile.installedData() {
                            Button(tr("Use %@", ECIProfile.expectedName)) { use(data, named: ECIProfile.profileFilename, id: ECIProfile.id) }
                        } else {
                            Button(tr("Download PSO Coated v3 from ECI…"), action: downloadPSO)
                        }
                    }
                case nil:
                    Text(tr("Get it from the printer’s instructions and use Choose ICC Profile…."))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var profileMenu: some View {
        let bundled = ICCProfileSources.bundled.compactMap { profile in ICCProfileSources.bundledData(profile).map { (profile, $0) } }
        if !bundled.isEmpty {
            Section(tr("Included with Paper & Grain")) {
                ForEach(bundled, id: \.0) { profile, data in
                    Button(ICCProfileInfo(data)?.name ?? profile.filename) { use(data, named: profile.filename, id: profile.id) }
                }
            }
        }
        Section("ECI") {
            if psoInstalled, let data = ECIProfile.installedData() {
                Button("PSO Coated v3") { use(data, named: ECIProfile.profileFilename, id: ECIProfile.id) }
            } else {
                Button(tr("Download PSO Coated v3 from ECI…"), action: downloadPSO)
            }
        }
        if !installed.isEmpty {
            Section(tr("On This Mac")) {
                ForEach(installed, id: \.url) { profile in
                    Button(profile.name) { useInstalled(profile) }
                }
            }
        }
        Divider()
        Button(tr("Choose ICC Profile…"), action: chooseFile)
    }

    /// Chooses the profile the printer names when it is at hand (bundled, installed or already downloaded).
    private func preselect() {
        switch candidate {
        case let .bundled(profile)?:
            if let data = ICCProfileSources.bundledData(profile) { use(data, named: profile.filename, id: profile.id) }
        case let .installed(profile)?:
            useInstalled(profile)
        case .eci?:
            if let data = ECIProfile.installedData() { use(data, named: ECIProfile.profileFilename, id: ECIProfile.id) }
        case nil:
            break
        }
    }

    private func useInstalled(_ profile: ICCProfileSources.Installed) {
        guard let data = try? Data(contentsOf: profile.url) else { return }
        use(data, named: profile.url.lastPathComponent, id: "installed:" + profile.url.lastPathComponent)
    }

    private func use(_ data: Data, named name: String, id: String) {
        guard directory != nil else { return }
        do {
            let reference = try BookStorage.iccProfileReference(data, named: name, id: id)
            pending = PendingICCProfile(data: data, reference: reference)
            output = .cmyk(reference)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "icc"), .init(filenameExtension: "icm")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let readable = url.startAccessingSecurityScopedResource()
            defer { if readable { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            use(data, named: url.lastPathComponent, id: "file:" + url.lastPathComponent)
        }
    }

    private func downloadPSO() {
        downloading = true
        problem = nil
        Task {
            do {
                let data = try await ECIProfile.install()
                psoInstalled = true
                use(data, named: ECIProfile.profileFilename, id: ECIProfile.id)
            } catch {
                problem = error.localizedDescription + " "
                    + tr("Download it by hand from eci.org and use Choose ICC Profile….")
            }
            downloading = false
        }
    }
}

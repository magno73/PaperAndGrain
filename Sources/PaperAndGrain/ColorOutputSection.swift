import AppKit
import SwiftUI

/// **Book & Print › Color**: sRGB, or CMYK with an output profile. A profile chosen here (bundled, PSO
/// Coated v3 from ECI, installed on the Mac, or a file) is copied into the book package at once, so the
/// book carries the profile it prints with.
struct ColorOutputSection: View, Localizing {
    @Binding var output: ColorOutput?
    /// The book package; nil while the book has no package, when CMYK cannot be chosen.
    let directory: URL?
    /// The color mode the chosen print service asks for, if it names one the book does not use.
    let serviceAsks: PrintProfile.ColorMode?
    let language: String

    @State private var problem: String?
    @State private var downloading = false
    @State private var psoInstalled = ECIProfile.installedData() != nil
    @State private var installed: [ICCProfileSources.Installed] = []

    private var cmyk: Binding<Bool> {
        Binding(get: { output?.mode == .cmyk }, set: { on in
            output = on ? ColorOutput(mode: .cmyk, profile: output?.profile) : nil
        })
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
            if let serviceAsks {
                Text(serviceAsks == .cmyk ? tr("The print service asks for CMYK.") : tr("The print service asks for sRGB."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if output?.mode == .cmyk {
                Menu(output?.profile?.name ?? tr("Choose a Profile")) { profileMenu }
                    .help(tr("The CMYK output profile the printer names."))
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
        .task { installed = await Task.detached { ICCProfileSources.installed() }.value }
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
                    .help(tr("Contacts eci.org once to download ECI’s profile. The profile belongs to ECI."))
            }
        }
        if !installed.isEmpty {
            Section(tr("On This Mac")) {
                ForEach(installed, id: \.url) { profile in
                    Button(profile.name) {
                        guard let data = try? Data(contentsOf: profile.url) else { return }
                        use(data, named: profile.url.lastPathComponent, id: "installed:" + profile.url.lastPathComponent)
                    }
                }
            }
        }
        Divider()
        Button(tr("Choose ICC Profile…"), action: chooseFile)
    }

    private func use(_ data: Data, named name: String, id: String) {
        guard let directory else { return }
        do {
            let reference = try BookStorage.importICCProfile(data, named: name, id: id, in: directory)
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
                problem = (error.localizedDescription) + " "
                    + tr("Download it by hand from eci.org and use Choose ICC Profile….")
            }
            downloading = false
        }
    }
}

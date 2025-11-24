import SwiftUI
import SwiftData

struct SignScan: Model {
    @Attribute(.unique) var id: UUID
    @Bindable var ocrText: String
    @Bindable var latitude: Double
    @Bindable var longitude: Double
    @Bindable var photoFilename: String?

    init(id: UUID = UUID(), ocrText: String = "", latitude: Double = 0, longitude: Double = 0, photoFilename: String? = nil) {
        self.id = id
        self.ocrText = ocrText
        self.latitude = latitude
        self.longitude = longitude
        self.photoFilename = photoFilename
    }
}

struct SignScanEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var scan: SignScan
    @Environment(\.dismiss) private var dismiss

    init(scan: SignScan) {
        self._scan = .init(initialValue: scan)
    }

    var body: some View {
        Form {
            Section("OCR Text") {
                TextEditor(text: $scan.ocrText)
                    .frame(minHeight: 100)
            }
            Section("Location") {
                TextField("Latitude", value: $scan.latitude, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Longitude", value: $scan.longitude, format: .number)
                    .keyboardType(.decimalPad)
            }
            Section("Photo Filename (optional)") {
                TextField("Photo Filename", text: Binding($scan.photoFilename, replacingNilWith: ""))
            }
        }
        .navigationTitle("Edit SignScan")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    modelContext.insert(scan)
                    try? modelContext.save()
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith defaultValue: String) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in
                source.wrappedValue = newValue.isEmpty ? nil : newValue
            }
        )
    }
}

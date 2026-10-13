import SwiftUI
import SwiftData
import PhotosUI

struct SpotPhotosView: View {
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isCamera = false
    @State private var takenImage: UIImage? = nil

    var body: some View {
        List {
            if spot.streetPhotoFilenames.isEmpty {
                Text("No photos yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(spot.streetPhotoFilenames, id: \.self) { filename in
                    HStack {
                        if let image = ImageStore.loadImage(named: filename, context: context) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipped()
                                .cornerRadius(6)
                        } else {
                            Image(systemName: "photo")
                                .frame(width: 64, height: 64)
                        }
                        Text(filename)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete { indexSet in
                    let names = indexSet.map { spot.streetPhotoFilenames[$0] }
                    spot.streetPhotoFilenames.remove(atOffsets: indexSet)
                    guard context.saveOrReport() else { return }
                    do { for n in names { try ImageStore.deleteImage(named: n, context: context) } }
                    catch { AppIssueStore.shared.message = "Couldn’t remove photo data: \(error.localizedDescription)" }
                }
            }
        }
        .navigationTitle("Spot Photos")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Add from Library", systemImage: "photo")
                }
                Button {
                    isCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task { await importFromPicker(item) }
        }
        .sheet(isPresented: $isCamera) {
            CameraPicker { image in
                takenImage = image
                Task { await saveTakenImage() }
            } onCancel: {
                isCamera = false
            }
        }
    }

    private func importFromPicker(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                let filename = try ImageStore.saveJPEG(image, context: context)
                spot.addStreetPhoto(filename: filename)
                context.saveOrReport()
            }
        } catch { AppIssueStore.shared.message = "Couldn’t import photo: \(error.localizedDescription)" }
    }

    private func saveTakenImage() async {
        guard let image = takenImage else { return }
        do {
            let filename = try ImageStore.saveJPEG(image, context: context)
            spot.addStreetPhoto(filename: filename)
            context.saveOrReport()
        } catch { AppIssueStore.shared.message = "Couldn’t save photo: \(error.localizedDescription)" }
        isCamera = false
    }
}

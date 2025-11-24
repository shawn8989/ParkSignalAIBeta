import SwiftUI
import SwiftData

struct CarListView: View {
    @Environment(\.modelContext) private var context
    @Query private var cars: [Car]

    @State private var showAdd = false
    @State private var nickname = ""
    @State private var licensePlate = ""
    @State private var colorHex = ""
    @State private var iconName = "car.fill"

    var body: some View {
        NavigationStack {
            List {
                if cars.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No cars yet")
                            .font(.headline)
                        Text("Add your car to track parking sessions and alarms.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(cars, id: \.id) { car in
                    HStack(spacing: 12) {
                        Image(systemName: car.iconName)
                            .foregroundStyle(.accent)
                        VStack(alignment: .leading) {
                            Text(car.nickname)
                                .font(.headline)
                            if let plate = car.licensePlate, !plate.isEmpty {
                                Text(plate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteCars)
            }
            .navigationTitle("Cars")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add Car", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Nickname", text: $nickname)
                            TextField("License Plate (optional)", text: $licensePlate)
                            TextField("Color Hex (optional)", text: $colorHex)
                            TextField("SF Symbol (optional)", text: $iconName)
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .navigationTitle("New Car")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { resetForm(); showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { addCar() }
                                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func addCar() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return }
        let car = Car(
            nickname: trimmedNickname,
            licensePlate: licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licensePlate,
            colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : colorHex,
            iconName: iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "car.fill" : iconName
        )
        context.insert(car)
        try? context.save()
        resetForm()
        showAdd = false
    }

    private func resetForm() {
        nickname = ""
        licensePlate = ""
        colorHex = ""
        iconName = "car.fill"
    }

    private func deleteCars(at offsets: IndexSet) {
        let targets = offsets.map { cars[$0] }
        for car in targets {
            context.delete(car)
        }
        try? context.save()
    }
}

#Preview {
    CarListView()
        .modelContainer(for: [Car.self], inMemory: true)
}

ParkSignal AI 🚦🤖

Real-time parking sign interpretation. Instant clarity. Zero tickets.

ParkSignal AI is an iOS app that analyzes parking signs using AI — both live and from photos — to reveal real-time rules, restrictions, and parking safety signals. Powered by SwiftUI, SwiftData, Apple Vision, CoreLocation, MapKit, and OpenAI.

⸻

✨ Core Features

🚦 ParkSignal Live (Real-Time Interpreter)

Hold your camera up to a parking sign and get instant understanding.
	•	📷 Continuous live OCR
	•	🧠 AI-powered interpretation
	•	🔁 Deduped + stabilized text
	•	🎨 Real-time parking signal (green/red/yellow/blue/purple/gray)
	•	⚡ Immediate feedback — no saving in this mode
	•	❗ CTA: “Capture Photos to Save This Sign”

📸 Sign Capture (Photo-Based Analysis)

Capture and store sign data permanently.
	•	📷 Take 1 or multiple photos (stacked/multiple signs)
	•	👀 Review screen: Submit, Retake, Delete, Add More
	•	💾 Only saves when user presses Submit
	•	🔍 OCR + AI over all photos
	•	🧩 Merged text + unified restrictions
	•	📍 Saves address, location, signal, restrictions, photos
	•	🗺️ Adds to map + scan history

🧠 Multi-Photo Analysis Pipeline
	•	OCR per image
	•	Text merging
	•	AI parsing
	•	Clean, reliable restriction output

🎨 Color-Coded Parking Signals
	•	🟢 Safe
	•	🔴 Illegal now
	•	🟡 Restriction starting soon
	•	🔵 Permit/ADA only
	•	🟣 Metered / paid
	•	⚪ Unknown / incomplete

🛣️ Accurate Curb-Segment Logic

Parking rules apply only to the correct curb segment:
	•	Same side of street
	•	Within a 10–20 meter radius
	•	Opposite side = different rules

🗺️ Map Integration
	•	Each SignScan becomes a map pin
	•	Pin color = parking signal
	•	Tap → see photos, rules, address

🕑 History & Detail
	•	🖼️ Thumbnails
	•	🔍 OCR text
	•	📜 Parsed restrictions
	•	📍 Address
	•	🧭 Signal state
	•	🕰️ Timestamp

⸻

🛠️ Technology Stack

Platform
	•	📱 iOS (SwiftUI, iOS 17+)

Core Tech
	•	🧠 OpenAI API
	•	🧰 SwiftUI
	•	🗂️ SwiftData
	•	👁️ Apple Vision (OCR)
	•	📍 CoreLocation
	•	🗺️ MapKit
	•	🎥 Camera / AVCaptureSession

Architecture
	•	MVVM
	•	Modular features
	•	Multi-photo OCR pipeline
	•	SwiftData-backed SignScan repo
	•	Real-time signal engine

  📁 Project Structure
  test2/                     (app target — will be renamed)
│
├── App/
│   ├── ParkSignalApp.swift        (entry point, SwiftData container)
│   └── RootTabView.swift          (Scan / Map / History / Settings tabs)
│
├── Models/
│   ├── Models.swift               (ParkingSpot, Restriction, SignScan, ParkSession)
│   └── AIAnalysisModels.swift     (AI parsing DTOs)
│
├── Views/
│   ├── Scan/                      (ScanView, verdict UI, confirmation, camera, live scanner)
│   ├── Map/                       (MapTabView, SpotDetailView, SpotEditView)
│   ├── History/                   (HistoryTabView)
│   └── Settings/                  (SettingsView, AlarmListView)
│
├── Services/
│   ├── VisionOCRService.swift     (on-device OCR)
│   ├── ParkingTextParser.swift    (on-device sign parsing — works offline)
│   ├── AIAnalyzerService.swift    (optional OpenAI refinement)
│   ├── NotificationManager.swift  (restriction reminders)
│   ├── GeocodingService.swift · LocationManager.swift
│   ├── ImageStore.swift · AlarmService.swift
│
└── Utilities/
    ├── ParkingSignalStatus.swift  (signal colors + evaluation engine)
    └── Segment.swift · CurbGeometry.swift · DrivingSide.swift

Notes
	•	Guest-first: no account or login required.
	•	AI is optional: signs are parsed on-device first; an OpenAI key
		(Settings → AI Analysis) refines results when configured.

    
⸻

🗺️ Roadmap
	•	Enhanced curb segment modeling
	•	Background AI syncing
	•	User accounts + cloud backup
	•	Community scanning for reward points
	•	Offline mode
	•	Auto notifications for restrictions
	•	App Store launch prep

⸻

🌟 Vision

Parking signs shouldn’t feel like puzzles.

ParkSignal AI translates the city’s confusing metal hieroglyphs into instant, simple truth.

Zero confusion.
Zero doubt.
Zero tickets.

⸻

📄 License

License TBD (MIT recommended).

⸻

🤝 Contributions

Contributions welcome once core v1 is stable.

END

    

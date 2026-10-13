# Initialize the full development schema before deployment

On 2026-10-13, the signed-in CloudKit Console for team EU6247328G and
`iCloud.com.SOTech.ParkSignalAI` showed seven application record types in
Development. The production deployment preview proposed creating all seven;
Production had not received them. No Deploy action was taken.

The visible `CD_CurrentParking` type had only `CD_entityName`, `CD_id` and
`CD_parkedAt` application fields; the current model also has optional `spotID`.
Saving ordinary records does not prove that every optional model attribute has
been initialized on the server. Do not deploy this incomplete snapshot.

## Prepared developer tool

Debug builds accept the explicit launch argument `-InitializeCloudKitSchema`.
It calls Apple's `NSPersistentCloudKitContainer.initializeCloudKitSchema()` with
a managed object model generated from the same eight model types used by the app.
The initializer uses a separate temporary local store, unloads it, and leaves
the existing user store unchanged. Errors are surfaced. It is excluded from
Release and never runs during ordinary launches or unit tests.

This action writes representative schema records to CloudKit **Development**.
It requires an appropriately signed development build, the Development CloudKit
entitlement and a signed-in iCloud account. It is not a schema deployment, a
migration of Development records to Production, or a two-device sync test.

## Owner-assisted execution

1. Keep the existing device backup and the signed Release app available. Do not
   delete the app or reset its store. The current phone remains on Release; no
   replacement installation has been performed for this initializer.
2. Before using the phone, approve the temporary Debug installation and its
   Release-restoration procedure. Alternatively use a separately signed Simulator
   already signed into the same iCloud account. Unsigned CI/QA simulators do not
   have the required CloudKit entitlements.
3. In Xcode, select the development build and verify that its signed CloudKit
   environment is **Development**. Edit Scheme → Run → Arguments → add
   `-InitializeCloudKitSchema`. A signed Simulator additionally needs
   `-EnableCloudKitSimulator`.
4. Run once. Require the console message “ParkSignal development schema
   initialization completed” and no schema error; then disable the argument.
5. In CloudKit Console, Development → Record Types, verify the complete generated
   model, including `CD_CurrentParking.CD_spotID`, optional restriction fields,
   review flags/reasons, photo assets and every model's relationships/attributes.
6. Open Deploy Schema Changes and review the complete diff, including security
   roles. Obtain approval before applying the concrete Production change. Do not
   use Reset Environment or delete any record types.
7. After deployment, inspect Production record types/fields and deployment history.
   Test a Production-signed/TestFlight build on two devices with the same iCloud
   account: create a uniquely labeled spot with photo, verify it appears on the
   second device, edit it there, and verify the edit returns. Record evidence;
   account availability or a single transfer event is insufficient.

Reference: [Apple's SwiftData schema initialization procedure](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

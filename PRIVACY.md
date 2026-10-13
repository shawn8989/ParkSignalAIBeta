# ParkSignal AI — Privacy Policy

Effective October 12, 2026. This policy describes the free v1 release.

ParkSignal reads parking-sign text on your device and helps you save spots, cars,
photos, rules and reminders. It has no app account, advertising, analytics SDK or
OpenAI integration. We do not operate a server that receives your parking records.

## On-device processing and permissions

Camera and selected photo-library images are used for Apple's on-device text
recognition. You choose which photos to save. Location while using the app places
spots on the map. Apple Maps and address lookup use Apple's services and may
communicate location-related information to Apple. Camera and location access can
be changed in iOS Settings; manual saved-spot features do not need the camera.
Notifications and system alarms run on each device, subject to the permissions
you grant. Reminder preferences and scheduling records stay on that device.

## iCloud and backups

When iCloud is available and enabled for ParkSignal, SwiftData/CloudKit is configured
to synchronize your saved parking records and photo data through your private
CloudKit database associated with your Apple Account. This means those records
and photos can leave the device for Apple's iCloud service. The developer does
not receive a copy on a separate server. Sync can be delayed or unavailable;
Settings shows storage status. Do not treat this as a guarantee that every item
has been backed up until you have verified it on another device.

Apple's iCloud and device-backup settings and Apple's privacy policy apply to
those services. Turning off iCloud does not automatically delete existing cloud
copies. Deleting the app removes its local storage but may leave iCloud data or
system backups that can restore later.

## Retention and deletion

Your saved records remain until you delete them. Delete spots, scans or photos in
the app; when sync is working, the associated record deletions can propagate to
your other devices. If you want to remove iCloud copies, also use Apple's iCloud
storage controls. Backup retention is controlled by Apple and your account settings.
We cannot retrieve or delete your private CloudKit records from a developer server.

## Support and sharing

Support is available at https://github.com/shawn8989/ParkSignalAIBeta/issues.
Submitting an issue is optional and publishes what you write on GitHub. Do not
post license plates, home addresses, precise parking locations, account details
or private photos. GitHub's privacy policy applies to information you submit there.

## Tracking and future changes

ParkSignal does not include ads, cross-app tracking or sale of personal data.
Cloud AI and purchases are not part of this release. Any future cloud processing
will require updated disclosures and an explicit choice before content is sent.
This page will be updated if the app's practices change.

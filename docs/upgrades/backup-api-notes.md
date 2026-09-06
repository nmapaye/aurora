# Backup file APIs for the data ownership batch

The local Expo SDK 54 bundled module manifest specifies `expo-document-picker ~14.0.8`, `expo-file-system ~19.0.23`, and `expo-sharing ~14.0.8`. These are not yet installed. Add them only in the data ownership implementation batch, with the lockfile and native dependency workflow reviewed.

Official SDK 54 references checked during insights review:

- [DocumentPicker](https://docs.expo.dev/versions/v54.0.0/sdk/document-picker/). Use the system picker with `copyToCacheDirectory: true` so the selected JSON can be read immediately. Cancellation must leave current data intact.
- [FileSystem](https://docs.expo.dev/versions/v54.0.0/sdk/filesystem/). Inspect the installed SDK 54 types when implementing file creation and reading.
- [Sharing](https://docs.expo.dev/versions/v54.0.0/sdk/sharing/). Export a local JSON file through the system share UI.

Aurora owns its native Xcode project manually. Do not run prebuild or add iCloud storage capabilities for this local backup feature. Keep exports explicitly labeled unencrypted, exclude Sample Data and OS permission grants, validate imports before preview, and require explicit replace confirmation.

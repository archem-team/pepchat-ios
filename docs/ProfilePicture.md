# Profile picture and cover picture (settings)

Documentation for profile picture (avatar) and cover picture (background/banner) in user profile settings: where they are uploaded and updated, and file-size validation at save time.

## Where upload and update happen

- **UI and save flow:** [Revolt/Pages/Settings/ProfileSettings.swift](Revolt/Pages/Settings/ProfileSettings.swift)
- **HTTP:** [Revolt/Api/Http.swift](Revolt/Api/Http.swift) — `uploadFile(data:name:category:)`, `updateSelf(profile:)`
- **Payloads:** [Revolt/Api/Payloads.swift](Revolt/Api/Payloads.swift) — `ProfilePayload`, `ProfileContent`
- **File categories:** [Revolt/Api/Utils.swift](Revolt/Api/Utils.swift) — `FileCategory.avatar`, `FileCategory.background`

### Flow

1. User selects profile or cover image via `PhotosPicker`; selection is stored in `currentValues.avatar` or `currentValues.background` as `.local(Data)`.
2. On **Save**, validation runs (display name length, then image sizes — see below). If any check fails, an alert is shown and save does not proceed.
3. If validation passes, a `Task` runs: uploads any new avatar/background via `uploadFile` (categories `.avatar` and `.background`), then calls `updateSelf(profile:)` (PATCH `/users/@me`) with the returned file IDs in `ProfilePayload` (`avatar`, `profile.background`).
4. On success, `viewState.currentUser` is updated and the screen is popped.

## File-size validation (at save time)

Validation runs **only when the user taps Save**, not when picking the image.

### Limits

| Image        | Max size | Constant (in code)           |
|-------------|----------|-----------------------------|
| Profile (avatar) | 4 MB     | `maxProfileImageSize`       |
| Cover (background) | 6 MB  | `maxCoverImageSize`         |

Bytes: 4 MB = `4 * 1024 * 1024`, 6 MB = `6 * 1024 * 1024`.

### Behavior

- If the user has chosen a **new** profile image (`.local(data)`) and `data.count > maxProfileImageSize`: show alert **"Profile image size cannot be more than 4MB"** and do not start the save `Task`.
- If the user has chosen a **new** cover image (`.local(data)`) and `data.count > maxCoverImageSize`: show alert **"Cover image size cannot be more than 6MB"** and do not start the save `Task`.
- Checks are run in order: avatar first, then cover. Only the first violation triggers an alert; the user can fix both and save again.
- Alerts use `viewState.showAlert(message:icon:color:)` with `icon: .peptideInfo` and `color: .iconRed07`, consistent with other file-size errors (e.g. [Revolt/Pages/Channel/Settings/Server/ServerOverviewSettings.swift](Revolt/Pages/Channel/Settings/Server/ServerOverviewSettings.swift)).

### Implementation details

- Constants: `private let maxProfileImageSize = 4 * 1024 * 1024` and `private let maxCoverImageSize = 6 * 1024 * 1024` in `ProfileSettings`.
- Validation is added in the Save button action, after display-name validation and **before** the `Task { ... }` that performs upload and `updateSelf`.
- Only `.local(let data)` with non-nil `data` is checked; `.remote` (existing server image) is not validated on save.

## References

- AGENTS.md — project structure, ViewState, settings under `Revolt/Pages/Settings/`.
- Server icon/banner size limits (different screen): [Revolt/Pages/Channel/Settings/Server/ServerOverviewSettings.swift](Revolt/Pages/Channel/Settings/Server/ServerOverviewSettings.swift) (e.g. 2.5 MB icon, 6 MB banner).

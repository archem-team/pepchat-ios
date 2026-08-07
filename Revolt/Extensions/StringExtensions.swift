import Foundation

extension String {
    func replacingUserMentionTokens(
        fallback: String = "@unknown-user",
        usernameForUserId: (String) -> String?
    ) -> String {
        var result = self
        guard let regex = try? NSRegularExpression(pattern: "<@([A-Za-z0-9]+)>") else {
            return result
        }

        let matches = regex.matches(
            in: result,
            range: NSRange(location: 0, length: result.utf16.count)
        )

        for match in matches.reversed() {
            guard let idRange = Range(match.range(at: 1), in: result),
                  let mentionRange = Range(match.range, in: result) else {
                continue
            }

            let userId = String(result[idRange])
            let replacement = usernameForUserId(userId).map { "@\($0)" } ?? fallback
            result.replaceSubrange(mentionRange, with: replacement)
        }

        return result
    }

    func convertMentionsToUsernames(viewState: ViewState) -> String {
        replacingUserMentionTokens { userId in
            guard let user = viewState.users[userId] ?? viewState.allEventUsers[userId] else {
                return nil
            }
            return user.display_name ?? user.username
        }
    }
    
    func containsMention() -> Bool {
        let pattern = "<@([A-Za-z0-9]+)>"
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: self.utf16.count)
            return regex.firstMatch(in: self, range: range) != nil
        } catch {
            print("DEBUG: Error checking for mentions: \(error)")
            return false
        }
    }
}

import Foundation

extension String {
    func convertMentionsToUsernames(viewState: ViewState) -> String {
        var result = self
        
        // Regular expression to match mention format: <@user_id>
        let pattern = "<@([A-Z0-9]+)>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: result.utf16.count)
            
            // Find all matches
            let matches = regex.matches(in: result, range: range)
            
            // Process matches in reverse to avoid index issues
            for match in matches.reversed() {
                if let userIdRange = Range(match.range(at: 1), in: result) {
                    let userId = String(result[userIdRange])
                    
                    // Try to find user in viewState
                    if let user = viewState.users[userId] {
                        // Replace the mention with username
                        let mentionRange = Range(match.range, in: result)!
                        let username = user.display_name ?? user.username
                        result.replaceSubrange(mentionRange, with: "@\(username)")
                    }
                }
            }
        } catch {
            print("DEBUG: Error creating regex: \(error)")
        }
        
        return result
    }
    
    func containsMention() -> Bool {
        let pattern = "<@([A-Z0-9]+)>"
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
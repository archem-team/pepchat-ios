import SwiftUI

struct FriendRequestCard: View {
    let users: [User] // Array of users with requests
    let count: Int // Number of requests

    var body: some View {
        HStack {
            // Display avatars for the first two users
            ForEach(users.prefix(2), id: \.id) { user in
                Avatar(user: user, width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2)) // Optional: Add a border
            }
            
            // If there are more than two users, show a count
            if count > 2 {
                Text("+\(count - 2)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.leading, 5)
            }
            
            VStack(alignment: .leading) {
                Text("Incoming Friend Request")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("From \(users.map { $0.username }.joined(separator: ", ")) and \(count - 1) more")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            // Arrow icon for navigation
            Image(systemName: "chevron.right")
                .foregroundColor(.purple)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
    }
} 
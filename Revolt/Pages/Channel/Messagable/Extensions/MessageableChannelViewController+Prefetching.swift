//
//  MessageableChannelViewController+Prefetching.swift
//  Revolt
//
//  Extracted from MessageableChannelViewController.swift
//

import UIKit
import Kingfisher
import Types

// MARK: - UITableViewDataSourcePrefetching
extension MessageableChannelViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // Pre-cache message data for upcoming rows
        for indexPath in indexPaths {
            if indexPath.row < viewModel.messages.count {
                let messageId = viewModel.messages[indexPath.row]
                if let message = viewModel.viewState.messages[messageId],
                   let author = viewModel.viewState.users[message.author] {
                    
                    // Pre-load author's avatar
                    let member = viewModel.getMember(message: message).wrappedValue
                    let avatarInfo = viewModel.viewState.resolveAvatarUrl(user: author, member: member, masquerade: message.masquerade)
                    
                    // Fix: Only create the URL array if the URL is valid
                    if let url = URL(string: avatarInfo.url.absoluteString) {
                        // Use Kingfisher's ImagePrefetcher with the URL - make sure to not pass any arguments to start()
                        let prefetcher = ImagePrefetcher(urls: [url])
                        prefetcher.start()
                    }
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        // Cancel pre-fetching for rows that are no longer needed
        // Not critical to implement, but helps save resources
    }
}

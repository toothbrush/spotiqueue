//
//  RBSearchTableView.swift
//  Spotiqueue
//
//  Created by Paul on 20/5/21.
//  Copyright © 2021 Rustling Broccoli. All rights reserved.
//

import Cocoa
import Combine

class RBQueueTableView: RBTableView {
    var cancellables: Set<AnyCancellable> = []

    override func associatedArrayController() -> NSArrayController {
        AppDelegate.appDelegate().queueArrayController
    }

    @objc func paste(_ sender: AnyObject?) {
        AppDelegate.appDelegate().isSearching = true
        guard let contents = NSPasteboard.general.pasteboardItems?.first?.string(forType: .string) else { return }
        addTracksToQueue(from: contents)
    }

    func addTracksToQueue(from contents: String) {
        AppDelegate.appDelegate().isSearching = true
        let incoming_uris = RBSpotify.sanitiseIncomingURIBlob(pasted_blob: contents)
        guard !incoming_uris.isEmpty else {
            AppDelegate.appDelegate().isSearching = false
            return
        }
        
        if incoming_uris.allSatisfy({ $0.uri.hasPrefix("spotify:track:") }) {
            // we can use the fancy batching-fetch-songs mechanism.
            var stub_songs: [RBSpotifySongTableRow] = []
            for s in incoming_uris {
                logger.info("Hydrating song \(s)")
                stub_songs.append(
                    RBSpotifySongTableRow(spotify_uri: s.uri)
                )
            }
            AppDelegate.appDelegate().queueArrayController.add(contentsOf: stub_songs)
            
            AppDelegate.appDelegate().runningTasks = Int((Double(stub_songs.count) / 50.0).rounded(.up))
            for chunk in stub_songs.chunked(size: 50) {
                AppDelegate.appDelegate().spotify.api.tracks(chunk.map({ $0.spotify_uri }))
                    .receive(on: RunLoop.main)
                    .sink(
                        receiveCompletion: { completion in
                            AppDelegate.appDelegate().runningTasks -= 1
                            logger.info("completion: \(completion)")
                        },
                        receiveValue: { tracks in
                            for (index, track) in tracks.enumerated() {
                                logger.info("result[\(index)]: \(track?.name ?? "")")
                                if let track = track {
                                    chunk[index].hydrate(with: track)
                                } else {
                                    // we got a nil from the API, remove from queue.
                                }
                            }
                        }
                    )
                    .store(in: &cancellables)
            }
        } else {
            // deal with pasted items one-by-one
            Publishers.mergeMappedRetainingOrder(incoming_uris,
                                                 mapTransform: { AppDelegate.appDelegate().spotify.api.dealWithUnknownSpotifyURI($0) })
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    AppDelegate.appDelegate().isSearching = false
                    logger.info("completion: \(completion)")
                },
                receiveValue: { tracks in
                    AppDelegate.appDelegate()
                        .insertTracks(newRows: tracks.joined().map({ RBSpotifySongTableRow(track: $0)}),
                                      in: .Queue,
                                      at_the_top: false,
                                      and_then_advance: false)
                })
                .store(in: &cancellables)
        }
    }
    
    func enter() {
        guard self.selectedRowIndexes.count == 1 else {
            logger.info("hmm, enter pressed on non-single track selection..")
            NSSound.beep()
            return
        }
        AppDelegate.appDelegate().queue.removeFirst(self.selectedRow)
        AppDelegate.appDelegate().playNextQueuedTrack()
    }

    func delete() {
        guard self.selectedRowIndexes.count > 0 else {
            NSSound.beep()
            return
        }
        let firstDeletionIdx = self.selectedRowIndexes.first!
        AppDelegate.appDelegate().queue.remove(atOffsets: self.selectedRowIndexes)
        self.selectRow(row: firstDeletionIdx)
    }

    override func browseDetailsOnRow() {
        guard !AppDelegate.appDelegate().isSearching else {
            return
        }
        guard selectedRowIndexes.count == 1 else {
            NSSound.beep()
            return
        }

        // ugh, there should probably be a "do_stuff_before_searching" in which to factor this stuff out, but oh well.
        AppDelegate.appDelegate().isSearching = true
        AppDelegate.appDelegate().searchResults = []
        AppDelegate.appDelegate().filterResultsField.clearFilter()
        AppDelegate.appDelegate().window.makeFirstResponder(AppDelegate.appDelegate().searchTableView)
        if let songRow: RBSpotifySongTableRow = self.associatedArrayController().selectedObjects.first as? RBSpotifySongTableRow {
            AppDelegate.appDelegate().albumTracks(for: songRow.spotify_album)
        }
    }

    func moveSelectionUp() {
        guard !self.selectedRowIndexes.isEmpty else {
            NSSound.beep()
            return
        }
        if let first = self.selectedRowIndexes.first, first > 0 {
            AppDelegate.appDelegate().queue.move(fromOffsets: self.selectedRowIndexes, toOffset: first - 1)
            self.scrollRowToVisible((first - 2).clamped(fromInclusive: 0, toInclusive: self.numberOfRows - 1))
        }
    }

    func moveSelectionDown() {
        guard !self.selectedRowIndexes.isEmpty else {
            NSSound.beep()
            return
        }
        if let last = self.selectedRowIndexes.last, last + 1 < self.numberOfRows  {
            AppDelegate.appDelegate().queue.move(fromOffsets: self.selectedRowIndexes, toOffset: last + 2)
            self.scrollRowToVisible((last + 2).clamped(fromInclusive: 0, toInclusive: self.numberOfRows - 1))
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
        if event.keyCode == kVK_Return
            && flags.isEmpty { // Enter/Return key
            enter()
        } else if (event.keyCode == kVK_Delete         // Backspace
                    || event.keyCode == kVK_ForwardDelete   // Delete
                    || event.characters == "d")
                    && flags.isEmpty {
            delete()
        } else if event.keyCode == kVK_DownArrow       // down arrow
                    && flags == [.command] {
            moveSelectionDown()
        } else if event.keyCode == kVK_UpArrow       // up arrow
                    && flags == [.command] {
            moveSelectionUp()
        } else {
            super.keyDown(with: event)
        }
    }
}

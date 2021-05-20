// Copyright 2021 Google LLC. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import GoogleCast

/** A key for the URL of the media item's poster (large image). */
let kMediaKeyPosterURL = "posterUrl"
/** A key for the media item's extended description. */
let kMediaKeyDescription = "description"
let kKeyCategories = "categories"
let kKeyHlsBaseURL = "hls"
let kKeyImagesBaseURL = "images"
let kKeyTracksBaseURL = "tracks"
let kKeySources = "sources"
let kKeyVideos = "videos"
let kKeyArtist = "artist"
let kKeyBaseURL = "baseUrl"
let kKeyContentID = "contentId"
let kKeyDescription = "description"
let kKeyID = "id"
let kKeyImageURL = "image-480x270"
let kKeyItems = "items"
let kKeyLanguage = "language"
let kKeyMimeType = "mime"
let kKeyName = "name"
let kKeyPosterURL = "image-780x1200"
let kKeyStreamType = "streamType"
let kKeyStudio = "studio"
let kKeySubtitle = "subtitle"
let kKeySubtype = "subtype"
let kKeyTitle = "title"
let kKeyTracks = "tracks"
let kKeyType = "type"
let kKeyURL = "url"
let kKeyDuration = "duration"
let kDefaultVideoMimeType = "application/x-mpegurl"
let kDefaultTrackMimeType = "text/vtt"
let kTypeAudio = "audio"
let kTypePhoto = "photos"
let kTypeVideo = "videos"
let kTypeLive = "live"
let kThumbnailWidth = 480
let kThumbnailHeight = 720
let kPosterWidth = 780
let kPosterHeight = 1200

/**
 * The delegate protocol for receiving notifications from the model.
 */
protocol MediaListModelDelegate: NSObjectProtocol {
  /**
   * Called when the media list has loaded.
   *
   * @param list The media list.
   */
  func mediaListModelDidLoad(_ list: MediaListModel)

  /**
   * Called when the media list has failed to load.
   *
   * @param list The media list.
   * @param error The error.
   */
  func mediaListModel(_ list: MediaListModel, didFailToLoadWithError error: Error?)
}

/**
 * An object representing a hierarchy of media items.
 */
class MediaListModel: NSObject {
  private var request: URLRequest!
  private var connection: NSURLConnection!
  private var responseData: Data!
  private var responseStatus: Int = 0
  private var trackStyle: GCKMediaTextTrackStyle!
  private var session: URLSession
  private var config: URLSessionConfiguration
  private var task: URLSessionTask
  /* The root item (top-level group). */
  fileprivate(set) var rootItem: MediaItem!

  /** A delegate for receiving notifications from the model. */
  weak var delegate: MediaListModelDelegate?
  /** A flag indicating whether the model has been loaded. */
  fileprivate(set) var isLoaded: Bool = false
  /** The title of the media list. */
  fileprivate(set) var title: String = ""

  /** Storage for the list of Media objects. */
  var medias = [Any]()

  /**
   * Begins loading the model from the given URL. The delegate will be messaged
   * when the load
   * completes or fails.
   *
   * @param url The URL of the JSON file describing the media hierarchy.
   */
  
  func load(from url: URL) {
    rootItem = nil
    request = URLRequest(url: url)
    responseData = nil
    
    config = URLSessionConfiguration.default
    session = URLSession(configuration: config)
    task = session.dataTask(with: request, completionHandler: {(data, response, error) in
      
      guard error == nil else {
        GCKLogger.sharedInstance().delegate?.logMessage?("httpRequest failed with \(String(describing: error))", at: .debug, fromFunction: #function, location: "MediaListModel.class")
        self.delegate?.mediaListModel(self, didFailToLoadWithError: error)
        return
      }
      
      guard let resp = response as? HTTPURLResponse, (200...299).contains(resp.statusCode) else {
        GCKLogger.sharedInstance().delegate?.logMessage?("httpRequestCompleted with \(String(describing: response)))", at: .debug, fromFunction: #function, location: "MediaListModel.class")
        return
      }
      
      guard data != nil else {
        self.responseData = Data()
        return
      }
      
      do {
        self.responseStatus = resp.statusCode
        self.responseData = data
        if(self.responseStatus == 200) {
          let jsonData = (try? JSONSerialization.jsonObject(with: self.responseData,
                                                            options: .mutableContainers)) as? NSDictionary
          self.rootItem = self.decodeMediaTree(fromJSON: jsonData!)
          self.isLoaded = true
          self.delegate?.mediaListModelDidLoad(self)
        } else {
          let error = NSError(domain: "HTTP", code: self.responseStatus, userInfo: nil)
          self.delegate?.mediaListModel(self, didFailToLoadWithError: error)
        }
      }
    })
    task.resume()
  }
  
  override init() {
    config = URLSessionConfiguration()
    session = URLSession()
    task = URLSessionTask()
    super.init()
    trackStyle = GCKMediaTextTrackStyle.createDefault()
  }

  func cancelLoad() {
    if request != nil {
      task.cancel()
      request = nil
      responseData = nil
    }
  }

  // MARK: - JSON decoding

  func decodeMediaTree(fromJSON json: NSDictionary) -> MediaItem {
    let rootItem = MediaItem(title: nil, imageURL: nil, parent: nil)
    let categories = json.gck_array(forKey: kKeyCategories)!
    for categoryElement in categories {
      if !(categoryElement is [AnyHashable: Any]) {
        continue
      }
      let category = (categoryElement as? NSDictionary)
      let mediaList = category?.gck_array(forKey: kKeyVideos)
      if mediaList != nil {
        title = (category?.gck_string(forKey: kKeyName))!
        // Pick the MP4 files only
        let videosBaseURLString: String? = category?.gck_string(forKey: kKeyHlsBaseURL)
        let videosBaseURL = URL(string: videosBaseURLString!)
        let imagesBaseURLString: String? = category?.gck_string(forKey: kKeyImagesBaseURL)
        let imagesBaseURL = URL(string: imagesBaseURLString!)
        let tracksBaseURLString: String? = category?.gck_string(forKey: kKeyTracksBaseURL)
        let tracksBaseURL = URL(string: tracksBaseURLString!)
        decodeItemList(fromArray: mediaList!, into: rootItem, videoFormat: kKeyHlsBaseURL,
                       videosBaseURL: videosBaseURL!, imagesBaseURL: imagesBaseURL!, tracksBaseURL: tracksBaseURL!)
        break
      }
    }
    return rootItem
  }

  func buildURL(with string: String?, baseURL: URL) -> URL? {
    guard let string = string else { return nil }
    if string.hasPrefix("http://") || string.hasPrefix("https://") {
      return URL(string: string)!
    } else {
      return URL(string: string, relativeTo: baseURL)!
    }
  }

  func decodeItemList(fromArray array: [Any], into item: MediaItem, videoFormat: String,
                      videosBaseURL: URL, imagesBaseURL: URL, tracksBaseURL: URL) {
    for element in array {
      if let dict = element as? NSDictionary {
        let metadata = GCKMediaMetadata(metadataType: .movie)
        if let title = dict.gck_string(forKey: kKeyTitle) {
          metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        }
        var mimeType: String?
        var url: URL?
        let sources: [Any] = dict.gck_array(forKey: kKeySources) ?? []
        for sourceElement in sources {
          if let sourceDict = sourceElement as? NSDictionary {
            let type: String? = sourceDict.gck_string(forKey: kKeyType)
            if type == videoFormat {
              mimeType = sourceDict.gck_string(forKey: kKeyMimeType)
              let urlText: String? = sourceDict.gck_string(forKey: kKeyURL)
              url = buildURL(with: urlText, baseURL: videosBaseURL)
              break
            }
          }
        }
        let imageURLString: String? = dict.gck_string(forKey: kKeyImageURL)
        if let imageURL = self.buildURL(with: imageURLString, baseURL: imagesBaseURL) {
          metadata.addImage(GCKImage(url: imageURL, width: kThumbnailWidth, height: kThumbnailHeight))
        }
        let posterURLText: String? = dict.gck_string(forKey: kKeyPosterURL)
        if let posterURL = self.buildURL(with: posterURLText, baseURL: imagesBaseURL) {
          metadata.setString(posterURL.absoluteString, forKey: kMediaKeyPosterURL)
          metadata.addImage(GCKImage(url: posterURL, width: kPosterWidth, height: kPosterHeight))
        }
        if let description = dict.gck_string(forKey: kKeySubtitle) {
          metadata.setString(description, forKey: kMediaKeyDescription)
        }
        var mediaTracks: [GCKMediaTrack]?
        if let studio = dict.gck_string(forKey: kKeyStudio) {
          metadata.setString(studio, forKey: kGCKMetadataKeyStudio)
        }
        let duration: Int? = dict.gck_integer(forKey: kKeyDuration)
        mediaTracks = [GCKMediaTrack]()
        if let tracks = dict.gck_array(forKey: kKeyTracks) {
          for trackElement: Any in tracks {
            guard let trackDict = trackElement as? NSDictionary else { continue }
            let identifier = trackDict.gck_integer(forKey: kKeyID)
            let name: String? = trackDict.gck_string(forKey: kKeyName)
            let typeString: String? = trackDict.gck_string(forKey: kKeyType)
            let subtypeString: String? = trackDict.gck_string(forKey: kKeySubtype)
            let contentID: String? = trackDict.gck_string(forKey: kKeyContentID)
            let language: String? = trackDict.gck_string(forKey: kKeyLanguage)
            let url = buildURL(with: contentID, baseURL: tracksBaseURL)
            let mediaTrack = GCKMediaTrack(identifier: identifier, contentIdentifier: url?.absoluteString,
                                           contentType: kDefaultTrackMimeType, type: trackType(from: typeString!),
                                           textSubtype: textTrackSubtype(from: subtypeString!),
                                           name: name, languageCode: language, customData: nil)
            mediaTracks?.append(mediaTrack)
          }
        }

        if mediaTracks?.count == 0 {
          mediaTracks = nil
        }

        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url!)
        // TODO: Remove contentID when sample receiver supports using contentURL
        mediaInfoBuilder.contentID = url!.absoluteString
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.streamDuration = TimeInterval(duration!)
        mediaInfoBuilder.contentType = mimeType!
        mediaInfoBuilder.metadata = metadata
        mediaInfoBuilder.mediaTracks = mediaTracks
        mediaInfoBuilder.textTrackStyle = trackStyle

        let mediaInfo = mediaInfoBuilder.build()
        let childItem = MediaItem(mediaInformation: mediaInfo, parent: item)
        item.children.append(childItem)
      }
    }
  }

  func trackType(from string: String) -> GCKMediaTrackType {
    if string == "audio" {
      return .audio
    }
    if string == "text" {
      return .text
    }
    if string == "video" {
      return .video
    }
    return .unknown
  }

  func textTrackSubtype(from string: String) -> GCKMediaTextTrackSubtype {
    if string == "captions" {
      return .captions
    }
    if string == "chapters" {
      return .chapters
    }
    if string == "descriptions" {
      return .descriptions
    }
    if string == "metadata" {
      return .metadata
    }
    if string == "subtitles" {
      return .subtitles
    }
    return .unknown
  }
}

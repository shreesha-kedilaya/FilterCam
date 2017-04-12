//
//  MediaStitch.swift
//  FilterCam
//
//  Created by Shreesha on 21/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import AVFoundation

class MediaStitch {
    func mergeFilesWithUrl(videoUrl:URL, audioUrl:URL, renderSize: CGSize, savingUrl: URL, completion: @escaping filterCompletionBlock) {
        let mixComposition : AVMutableComposition = AVMutableComposition()
        var mutableCompositionVideoTrack : [AVMutableCompositionTrack] = []
        var mutableCompositionAudioTrack : [AVMutableCompositionTrack] = []
        let totalVideoCompositionInstruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()

        let aVideoAsset : AVAsset = AVAsset(url: videoUrl)
        let aAudioAsset : AVAsset = AVAsset(url: audioUrl)
        let audioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let videoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)

        mutableCompositionVideoTrack.append(videoTrack)
        mutableCompositionAudioTrack.append(audioTrack)

        let aVideoAssetTrack : AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaTypeVideo)[0]
        let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaTypeAudio)[0]

        do{
            try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(kCMTimeZero, aVideoAssetTrack.timeRange.duration), of: aVideoAssetTrack, at: kCMTimeZero)

            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(kCMTimeZero, aVideoAssetTrack.timeRange.duration), of: aAudioAssetTrack, at: kCMTimeZero)

        } catch {
            completion(nil, error)
        }

        totalVideoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero,aVideoAssetTrack.timeRange.duration )

        let mutableVideoComposition : AVMutableVideoComposition = AVMutableVideoComposition()
        mutableVideoComposition.frameDuration = CMTimeMake(1, 30)

        mutableVideoComposition.renderSize = renderSize

        let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
        assetExport.outputFileType = AVFileTypeMPEG4
        assetExport.outputURL = savingUrl
        assetExport.shouldOptimizeForNetworkUse = true

        assetExport.exportAsynchronously { () -> Void in
            switch assetExport.status {

            case AVAssetExportSessionStatus.completed:
                completion(savingUrl, nil)
            case  AVAssetExportSessionStatus.failed:
                let error = NSError(domain: "Failed", code: 1200, userInfo: nil)
                completion(savingUrl, error)
            case AVAssetExportSessionStatus.cancelled:
                let error = NSError(domain: "Cancelled", code: 1201, userInfo: nil)
                completion(savingUrl, error)
            default:
                completion(savingUrl, nil)
            }
        }
    }
}

//
//  SoundService.swift
//  SpeechRecognizer
//
//  Created by Daniel Trostli on 1/24/18.
//  Copyright © 2018 trostli. All rights reserved.
//

import Foundation
import AVFoundation

class SoundService {
    
    //MARK: - Properties and data
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    static let sharedInstance = SoundService()
    
    private init() {}
    
    func openFileAndPlay() {
        
        if let path = Bundle.main.path(forResource: "sampl2", ofType: "hexformat") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                let pcm16Data: [Int16] = decodeAdpcm(data: data)!
                print("pcm16Data")
                print(pcm16Data)
                let buffer = prepareBuffer(pcm16Data: pcm16Data)
                startPlaying(buffer: buffer)
            } catch {
                // handle error
                print("error")
                
            }
        }

    }
    
    func startPlaying(buffer: AVAudioPCMBuffer) {
        // The pcmFormatInt16 format is not supported in AvAudioPlayerNode
        // Later on we will have to devide all values by Int16.max to get values from -1.0 to 1.0
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.volume = 1.0
        player.scheduleBuffer(buffer, completionHandler: nil)
        
        do {
            engine.prepare()
            try engine.start()
        } catch {
            print("AVAudioEngine.start() error: \(error.localizedDescription)")
        }
        player.play()
    }
    
    func prepareBuffer(pcm16Data: [Int16]) -> AVAudioPCMBuffer {
//        guard let engine = engine, engine.isRunning else {
//            // Streaming has been already stopped
//            return
//        }
        let audioFormat = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(pcm16Data.count))
        buffer.frameLength = buffer.frameCapacity
        
        for i in 0 ..< pcm16Data.count {
            buffer.floatChannelData![0 /* channel 1 */][i] = Float32(pcm16Data[i]) / Float32(Int16.max)
        }
        return buffer
    }
    
    //MARK: - ADPCM decoding
    
    /** Intel ADPCM step variation table */
    private static let indexTable : [Int] = [ -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8 ]
    
    /** ADPCM step size table */
    private static let stepTable : [Int16] = [ 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28,
                                               31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
                                               157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
                                               598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878,
                                               2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
                                               6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
                                               18500, 20350, 22385, 24623, 27086, 29794, 32767 ]
    
    private var frameBuffer = Data()
    
    // Converts microphone data to pcm16Data
    // Taken from:
    // https://github.com/NordicSemiconductor/IOS-Nordic-Thingy/blob/b2e38e96e5c64f9dadbb7a4cf184a4e833bf3eae/IOSThingyLibrary/Classes/Services/SoundService/ThingySoundService.swift#L270
    
    internal func decodeAdpcm(data: Data) -> [Int16]? {
        frameBuffer.append(data)
        
        // A ADPCM frame on Thingy ia 131 bytes long:
        // 2 bytes - predicted value
        // 1 byte  - index
        // 128 bytes - 256 4-bit samples convertable to 16-bit PCM
        if frameBuffer.count >= 131 {
            // Get the frame
            let currentFrame = frameBuffer
            // Clear the buffer
            frameBuffer.removeAll()
            
            // Read 16-bit predicted value
            var valuePredicted: Int32 = Int32(Int16(currentFrame[1]) | Int16(currentFrame[0]) << 8)
            // Read the first index
            var index = Int(currentFrame[2])
            
            var nextValue: UInt8 = 0 // value to be read from the frame
            var bufferStep = false   // should the first f second touple be read from nextValue as index delta
            var delta: UInt8 = 0     // index delta; each following frame is calculated based on the previous using an index
            var sign:  UInt8 = 0
            var step = SoundService.stepTable[index]
            var output = [Int16]()
            
            for i in 0 ..< (currentFrame.count - 3) * 2 { // 3 bytes have already been eaten
                if bufferStep {
                    delta = nextValue & 0x0F
                } else {
                    nextValue = currentFrame[3 + i / 2]
                    delta = (nextValue >> 4) & 0x0F
                }
                bufferStep = !bufferStep
                
                index += SoundService.indexTable[Int(delta)]
                index = min(max(index, 0), 88) // index must be <0, 88>
                
                sign  = delta & 8    // the first bit of delta is the sign
                delta = delta & 7    // the rest is a value
                
                var diff : Int32 = Int32(step >> 3)
                if (delta & 4) > 0 {
                    diff += Int32(step)
                }
                if (delta & 2) > 0 {
                    diff += Int32(step >> 1)
                }
                if (delta & 1) > 0 {
                    diff += Int32(step >> 2)
                }
                if sign > 0 {
                    valuePredicted -= diff
                } else {
                    valuePredicted += diff
                }
                
                let value: Int16 = Int16(min(Int32(Int16.max), max(Int32(Int16.min), valuePredicted)))
                
                step = SoundService.stepTable[index]
                output.append(value)
            }
            return output
        }
        return nil
    }

}

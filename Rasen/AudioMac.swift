// Copyright 2023 Cii
//
// This file is part of Rasen.
//
// Rasen is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Rasen is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Rasen.  If not, see <http://www.gnu.org/licenses/>.

// Copyright © 2023 Apple Inc.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import AVFAudio
import Accelerate

struct Biquad {
    private var filter: vDSP.Biquad<Double>
    init?(coefficients: [Double],
          channelCount: Int = 1, sectionCount: Int = 1) {
        guard let filter = vDSP.Biquad(coefficients: coefficients,
                                       channelCount: UInt(channelCount),
                                       sectionCount: UInt(sectionCount),
                                       ofType: Double.self) else { return nil }
        self.filter = filter
    }
    mutating func apply(input data: [Double]) -> [Double] {
        filter.apply(input: data)
    }
}

final class NotePlayer {
    private var aNotes: [Note.PitResult]
    var notes: [Note.PitResult] {
        get { aNotes }
        set {
            let oldValue = aNotes
            aNotes = newValue
            guard isPlaying,
                    aNotes.count == oldValue.count ?
                        (0 ..< notes.count).contains(where: { aNotes[$0] != oldValue[$0] }) :
                        true else { return }
            stopNote()
            playNote()
        }
    }
    func changeStereo(from notes: [Note.PitResult]) {
        self.notes = notes
//        self.aNotes = notes
//        if notes.count == noder.rendnotes.count {
//            noder.replaceVolumeOrPan(notes.enumerated().map { .init(value: $0.element, index: $0.offset) })
//        }
    }
    var volume: Volume {
        get { noder.volume }
        set { noder.volume = .init(amp: newValue.amp.clipped(min: Volume.minAmp, max: Volume.maxAmp)) }
    }
    var sequencer: Sequencer
    var noder: AVAudioScoreNoder
    var noteIDs = Set<UUID>()
    
    struct NotePlayerError: Error {}
    
    init(notes: [Note.PitResult],
         volume: Volume = .init(smp: Volume.maxSmp), pan: Double = 0,
         reverb: Double = Audio.defaultReverb) throws {
        
        guard let sequencer = Sequencer(audiotracks: [],
                                        isAsync: true, startSec: 0) else {
            throw NotePlayerError()
        }
        self.aNotes = notes
        self.sequencer = sequencer
        noder = .init(rendnotes: [],
                      startSec: 0, isAsync: true,
                      volumeAmp: volume.amp, pan: pan, reverb: reverb)
        sequencer.append(noder, id: UUID())
    }
    deinit {
        sequencer.endEngine()
    }
    
    var isPlaying = false
    
    func play() {
        timer.cancel()
        
        if isPlaying {
            stopNote()
        }
        if !sequencer.isPlaying {
            sequencer.play()
        } else {
            sequencer.startEngine()
        }
        playNote()
        
        isPlaying = true
    }
    private func playNote() {
        noteIDs = []
        noder.rendnotes += notes.map { note in
            let noteID = UUID()
            noteIDs.insert(noteID)
            return .init(fq: Pitch.fq(fromPitch: .init(note.notePitch) + note.pitch.doubleValue),
                         overtone: note.tone.overtone,
                         sourceFilter: note.tone.noiseSourceFilter(isNoise: note.isNoise),
                         fAlpha: 1,
                         isNoise: note.isNoise,
                         noiseSeed: Rendnote.noiseSeed(from: note.id),
                         pitbend: .empty,
                         secRange: -.infinity ..< .infinity,
                         startDeltaSec: 0,
                         volumeSmp: note.stereo.smp,
                         pan: note.stereo.pan,
                         envelopeMemo: .init(note.envelope),
                         sampleRate: noder.format.sampleRate,
                         dftCount: Audio.defaultDftCount,
                         id: noteID)
        }
    }
    private func stopNote() {
        let releaseStartSec = sequencer.currentPositionInSec + 0.05
        for (i, rendnote) in noder.rendnotes.enumerated() {
            if noteIDs.contains(rendnote.id) {
                noder.rendnotes[i].secRange.end = releaseStartSec
            }
        }
        noteIDs = []
    }
    
    static let stopEngineSec = 30.0
    private var timer = OneshotTimer()
    func stop() {
        stopNote()
        
        isPlaying = false
        
        timer.start(afterTime: max(NotePlayer.stopEngineSec, 
                                   (notes.maxValue { $0.envelope.releaseSec }) ?? 0),
                    dispatchQueue: .main) {
        } waitClosure: {
        } cancelClosure: {
        } endClosure: { [weak self] in
            self?.sequencer.stopEngine()
            self?.noder.rendnotes = []
        }
    }
}

final class AVAudioPCMNoder {
    fileprivate weak var sequencer: Sequencer?
    fileprivate var node: AVAudioSourceNode!
    
    init(pcmBuffer: PCMBuffer, startTime: Double,
         contentStartTime: Double, duration: Double,
         volumeAmp: Double, pan: Double, reverb: Double = Audio.defaultReverb) {
        let sampleRate = pcmBuffer.format.sampleRate
        let scst = startTime + contentStartTime
        let csSampleTime = -min(contentStartTime, 0) * sampleRate
        let cst = Int(csSampleTime)
        let frameLength = min(Int(pcmBuffer.frameLength),
                              Int((duration - min(contentStartTime, 0)) * sampleRate))
        let sampleFrameLength = min(Double(pcmBuffer.frameLength),
                                    (duration - min(contentStartTime, 0)) * sampleRate)
        node = AVAudioSourceNode(format: pcmBuffer.format) {
            [weak self]
            isSilence, timestamp, frameCount, outputData in

            guard let self,
                  let seq = self.sequencer else { return kAudioUnitErr_NoConnection }
            
            guard seq.isPlaying else {
                isSilence.pointee = true
                return noErr
            }
            guard let data = pcmBuffer.floatChannelData else { return kAudioUnitErr_NoConnection }
            
            let frameCount = Int(frameCount)
            let outputBLP
                = UnsafeMutableAudioBufferListPointer(outputData)
            for i in 0 ..< outputBLP.count {
                let nFrames = outputBLP[i].mData!
                    .assumingMemoryBound(to: Float.self)
                for j in 0 ..< frameCount {
                    nFrames[j] = 0
                }
            }
            
            if timestamp.pointee.mFlags.contains(.hostTimeValid) {
                let time = AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime - seq.startHostTime) + seq.startTime
                let sampleTime = (time - scst) * sampleRate
                
                guard sampleTime < sampleFrameLength - 1 && sampleTime + Double(frameCount) >= csSampleTime else {
                    isSilence.pointee = true
                    return noErr
                }
                
//                let outputBLP
//                    = UnsafeMutableAudioBufferListPointer(outputData)
//                for i in 0 ..< outputBLP.count {
//                    let nFrames = outputBLP[i].mData!
//                        .assumingMemoryBound(to: Float.self)
//                    for j in 0 ..< frameCount {
//                        nFrames[j] = 0
//                    }
//                }
                
                for i in 0 ..< outputBLP.count {
                    let oFrames = data[i]
                    let nFrames = outputBLP[i].mData!
                        .assumingMemoryBound(to: Float.self)
                    for j in 0 ..< frameCount {
                        let ni = sampleTime + Double(j)
                        if ni >= csSampleTime && ni < sampleFrameLength - 1 {
                            let rni = ni.rounded(.down)
                            let nii = Int(rni)
                            nFrames[j] = .linear(oFrames[nii],
                                                 oFrames[nii + 1],
                                                 t: ni - rni)
                            
                        }
                    }
                }
            } else if timestamp.pointee.mFlags.contains(.sampleTimeValid) {
                let timeI = Int(timestamp.pointee.mSampleTime - scst * sampleRate)
                
                guard timeI < frameLength && timeI + frameCount >= cst else {
                    isSilence.pointee = true
                    return noErr
                }
                
//                let outputBLP
//                    = UnsafeMutableAudioBufferListPointer(outputData)
//                for i in 0 ..< outputBLP.count {
//                    let nFrames = outputBLP[i].mData!
//                        .assumingMemoryBound(to: Float.self)
//                    for j in 0 ..< frameCount {
//                        nFrames[j] = 0
//                    }
//                }
                
                for i in 0 ..< outputBLP.count {
                    let oFrames = data[i]
                    let nFrames = outputBLP[i].mData!
                        .assumingMemoryBound(to: Float.self)
                    for j in 0 ..< frameCount {
                        let ni = timeI + j
                        if ni >= cst && ni < frameLength {
                            nFrames[j] = oFrames[ni]
                        }
                    }
                }
            } else {
                return kAudioUnitErr_NoConnection
            }
            
            return noErr
        }
        if volumeAmp != 1 {
            node.volume = Float(volumeAmp)
        }
        if pan != 0 {
            node.pan = Float(pan)
        }
    }
}

final class AVAudioScoreNoder {
    fileprivate weak var sequencer: Sequencer?
    fileprivate var node: AVAudioSourceNode!
    let format: AVAudioFormat
    
    var reverb: Double
    var volume: Volume {
        get { Volume(amp: Double(node.volume)) }
        set { node.volume = Float(newValue.amp) }
    }
    var pan: Double {
        get { Double(node.pan) }
        set { node.pan = Float(newValue) }
    }
    
    var rendnotes = [Rendnote]()
    var startSec = 0.0 {
        didSet { isSyncFirst = false }
    }
    var isAsync = true
    var isSyncFirst = true
    
    func insert(_ noteIVs: [IndexValue<Note>], with score: Score) {
        let nvs = noteIVs.map { IndexValue(value: Rendnote(note: $0.value, score: score,
                                                           startSec: startSec,
                                                           sampleRate: format.sampleRate), 
                                           index: $0.index) }
        
        let oNwids = Set(rendnotes.map { NotewaveID($0) })
        
        rendnotes.insert(nvs)
        
        let vs = nvs.reduce(into: [NotewaveID: Rendnote]()) {
            $0[NotewaveID($1.value)] = $1.value
        }
        for (nNwid, v) in vs {
            guard !oNwids.contains(nNwid) else { continue }
            
            workItems[nNwid]?.item?.cancel()
            workItems[nNwid]?.item = nil
            
            var item: DispatchWorkItem?
            item = DispatchWorkItem(qos: .userInitiated) { [weak self] in
                guard !(item?.isCancelled ?? true) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.workItems[nNwid]?.item = nil
                        self?.workItems[nNwid] = nil
                    }
                    item = nil
                    return
                }
                
                let notewave = v.notewave()
                
                DispatchQueue.main.async { [weak self] in
                    self?.notewaveDic[nNwid] = notewave
                    self?.workItems[nNwid]?.item = nil
                    self?.workItems[nNwid] = nil
                }
                item = nil
            }
            
            workItems[nNwid] = .init(item: item!)
            DispatchQueue.global(qos: .userInitiated).async(execute: item!)
        }
    }
    func replace(_ note: Note, at i: Int, with score: Score) {
        replace([.init(value: note, index: i)], with: score)
    }
    func replace(_ noteIVs: [IndexValue<Note>], with score: Score) {
        let nvs = noteIVs.map { IndexValue(value: Rendnote(note: $0.value, score: score,
                                                           startSec: startSec,
                                                           sampleRate: format.sampleRate),
                                           index: $0.index) }
        
        nvs.forEach { rendnotes[$0.index] = $0.value }
        
        let vs = nvs.reduce(into: [NotewaveID: Rendnote]()) {
            $0[NotewaveID($1.value)] = $1.value
        }
        for (key, v) in vs {
            workItems[key]?.item?.cancel()
            workItems[key]?.item = nil
            
            var item: DispatchWorkItem?
            item = DispatchWorkItem(qos: .userInitiated) { [weak self] in
                guard !(item?.isCancelled ?? true) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.workItems[key]?.item = nil
                        self?.workItems[key] = nil
                    }
                    item = nil
                    return
                }
                
                let notewave = v.notewave()
                
                DispatchQueue.main.async { [weak self] in
                    self?.notewaveDic[key] = notewave
                    self?.workItems[key]?.item = nil
                    self?.workItems[key] = nil
                }
                item = nil
            }
            
            workItems[key] = .init(item: item!)
            DispatchQueue.global(qos: .userInitiated).async(execute: item!)
        }
    }
    func replaceVolumeOrPan(_ noteIVs: [IndexValue<Note>], with score: Score) {
        noteIVs.forEach {
            rendnotes[$0.index].volumeSmp = 1
            rendnotes[$0.index].pan = 0
            rendnotes[$0.index].envelopeMemo = .init($0.value.envelope)
            rendnotes[$0.index].pitbend = $0.value.pitbend(fromTempo: score.tempo)
            
            let rendnoteID = rendnotes[$0.index].id
            memowaves[rendnoteID]?.volumeSmp = rendnotes[$0.index].volumeSmp
            memowaves[rendnoteID]?.pan = rendnotes[$0.index].pan
            memowaves[rendnoteID]?.envelopeMemo = rendnotes[$0.index].envelopeMemo
            memowaves[rendnoteID]?.pitbend = rendnotes[$0.index].pitbend
        }
    }
    func replaceVolumeOrPan(_ noteIVs: [IndexValue<Note.PitResult>]) {
        noteIVs.forEach {
            rendnotes[$0.index].volumeSmp = $0.value.stereo.volume.smp
            rendnotes[$0.index].pan = $0.value.stereo.pan
            rendnotes[$0.index].envelopeMemo = .init($0.value.envelope)
            
            let rendnoteID = rendnotes[$0.index].id
            memowaves[rendnoteID]?.volumeSmp = rendnotes[$0.index].volumeSmp
            memowaves[rendnoteID]?.pan = rendnotes[$0.index].pan
            memowaves[rendnoteID]?.envelopeMemo = rendnotes[$0.index].envelopeMemo
        }
    }
    func remove(at noteIs: [Int]) {
        let oNwids = Set(noteIs.map { NotewaveID(rendnotes[$0]) })
        
        noteIs.forEach { memowaves[rendnotes[$0].id] = nil }
        rendnotes.remove(at: noteIs)
        
        let nNwids = Set(rendnotes.map { NotewaveID($0) })
        
        for oNwid in oNwids {
            guard !nNwids.contains(oNwid) else { continue }
            workItems[oNwid]?.item?.cancel()
            workItems[oNwid]?.item = nil
            notewaveDic[oNwid] = nil
        }
    }
    
    deinit {
        cancelWorkItems()
    }
    
    struct WeakWorkItem {
        var item: DispatchWorkItem?
    }
    var workItems = [NotewaveID: WeakWorkItem]()
    func cancelWorkItems() {
        for key in workItems.keys {
            workItems[key]?.item?.cancel()
            workItems[key]?.item = nil
        }
        workItems = [:]
    }
    
    func updateRendnotes() {
        let ids = rendnotes.reduce(into: [NotewaveID: Rendnote]()) {
            $0[.init($1)] = $1
        }
        let removeNWIDs = notewaveDic.keys.filter { ids[$0] != nil }
        let insertNWIDs = ids.filter { notewaveDic[$0.key] == nil }
        for nwid in removeNWIDs {
            notewaveDic[nwid] = nil
        }
        let sortedINWIDs = insertNWIDs.sorted {
            $0.value.secRange.start < $1.value.secRange.start
        }
        let si = sortedINWIDs.enumerated().reversed()
            .first { ($0.element.value.secRange.start * 16 - 1) / 16 <= startSec }?.offset ?? 0
        let loopedINWIDs = sortedINWIDs.loop(from: si)
        let firstSec = loopedINWIDs.first?.value.secRange.start ?? 0
        for nwid in loopedINWIDs {
            if !isAsync || isSyncFirst && nwid.value.secRange.start == firstSec {
                notewaveDic[nwid.key] = nwid.value.notewave()
            } else {
                var item: DispatchWorkItem?
                item = DispatchWorkItem(qos: .userInitiated) { [weak self] in
                    guard !(item?.isCancelled ?? true) else {
                        DispatchQueue.main.async { [weak self] in
                            self?.workItems[nwid.key]?.item = nil
                            self?.workItems[nwid.key] = nil
                        }
                        item = nil
                        return
                    }
                    
                    let notewave = nwid.value.notewave()
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.notewaveDic[nwid.key] = notewave
                        self?.workItems[nwid.key]?.item = nil
                        self?.workItems[nwid.key] = nil
                    }
                    item = nil
                }
                
                workItems[nwid.key] = .init(item: item!)
                DispatchQueue.global(qos: .userInitiated)
                    .async(execute: item!)
            }
        }
    }
    
    struct NotewaveID: Hashable, Codable {
        var fq: Double,
            overtone: Overtone,
            sourceFilter: NoiseSourceFilter,
            fAlpha: Double,
            noiseSeed: UInt64,
            pitbend: Pitbend?,
            durSec: Double,
            startDeltaSec: Double
        
        init(_ rendnote: Rendnote) {
            fq = rendnote.fq
            overtone = rendnote.overtone
            sourceFilter = rendnote.sourceFilter
            fAlpha = rendnote.fAlpha
            noiseSeed = rendnote.noiseSeed
            pitbend = !rendnote.pitbend.isStereoOnly ? rendnote.pitbend : nil
            
            let loopDuration = rendnote.pitbend.isEmptyPitch || rendnote.pitbend.isEmptyTone ?
                1 : rendnote.envelopeMemo
                .duration(fromDurSec: rendnote.secRange.length)
            durSec = loopDuration
            startDeltaSec = rendnote.startDeltaSec
        }
    }
    private(set) var notewaveDic = [NotewaveID: Notewave]()
    
    struct Memowave {
        var startSec: Double, releaseSec: Double?, endSec: Double?,
            fq: Double, volumeSmp: Double, pan: Double, envelopeMemo: EnvelopeMemo, pitbend: Pitbend
        var notewave: Notewave
        
        func contains(sec: Double) -> Bool {
            if let endSec {
                return sec > startSec && sec < endSec
            } else {
                return sec > startSec
            }
        }
    }
    private var memowaves = [UUID: Memowave]()
    private var phases = [UUID: Double]()
    
    let semaphore = DispatchSemaphore(value: 1)
    
    init(rendnotes: [Rendnote],
         format: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: Audio.defaultSampleRate, channels: 2)!,
         startSec: Double, isAsync: Bool,
         volumeAmp: Double, pan: Double, reverb: Double = Audio.defaultReverb) {
        
        self.rendnotes = rendnotes
        self.format = format
        self.isAsync = isAsync
        self.startSec = startSec
        self.reverb = reverb
        
        let sampleRate = format.sampleRate
        let rSampleRate = 1 / sampleRate
        node = AVAudioSourceNode(format: format) {
            [weak self]
            isSilence, timestamp, frameCount, outputData in

            guard let self,
                  let seq = self.sequencer else { return kAudioUnitErr_NoConnection }
            
            guard seq.isPlaying else {
                isSilence.pointee = true
                return noErr
            }
            
            let frameCount = Int(frameCount)
            let outputBLP
                = UnsafeMutableAudioBufferListPointer(outputData)
            for i in 0 ..< outputBLP.count {
                let nFrames = outputBLP[i].mData!
                    .assumingMemoryBound(to: Float.self)
                for j in 0 ..< frameCount {
                    nFrames[j] = 0
                }
            }
            
            let sec: Double
            if timestamp.pointee.mFlags.contains(.hostTimeValid) {
                let dHostTime = timestamp.pointee.mHostTime > seq.startHostTime ?
                    timestamp.pointee.mHostTime - seq.startHostTime : 0
                let nSec = AVAudioTime.seconds(forHostTime: dHostTime) + seq.startTime
                sec = nSec
            } else if timestamp.pointee.mFlags.contains(.sampleTimeValid) {
                sec = timestamp.pointee.mSampleTime * rSampleRate
            } else {
                return kAudioUnitErr_NoConnection
            }
            
            self.semaphore.wait()
            let rendnotes = self.rendnotes
            self.semaphore.signal()
            for rendnote in rendnotes {
                let startSec = rendnote.secRange.start.isInfinite ?
                    sec : rendnote.secRange.start
                let secI = Int((sec - startSec) * sampleRate)
                if rendnote.secRange.end.isInfinite {
                    if secI + frameCount >= 0
                        && self.memowaves[rendnote.id] == nil {
                        
                        let nwid = NotewaveID(rendnote)
                        
                        let notewave: Notewave
                        if let nw = self.notewaveDic[nwid] {
                            notewave = nw
                        } else {
                            notewave = rendnote.notewave()
                            self.notewaveDic[nwid] = notewave
                        }
                        self.memowaves[rendnote.id]
                            = Memowave(startSec: startSec,
                                       releaseSec: nil,
                                       endSec: nil,
                                       fq: rendnote.fq,
                                       volumeSmp: rendnote.volumeSmp,
                                       pan: rendnote.pan,
                                       envelopeMemo: rendnote.envelopeMemo,
                                       pitbend: rendnote.pitbend,
                                       notewave: notewave)
                        self.phases[rendnote.id] = 0
                    }
                } else {
                    let length = rendnote.secRange.end - startSec
                    let durSec = rendnote.envelopeMemo.duration(fromDurSec: length)
                    let frameLength = Int(durSec * sampleRate)
                    if sec >= startSec
                        && startSec < rendnote.secRange.end
                        && secI < frameLength && secI + frameCount >= 0
                        && self.memowaves[rendnote.id] == nil {
                        
                        let nwid = NotewaveID(rendnote)
                        
                        let notewave: Notewave
                        if let nw = self.notewaveDic[nwid] {
                            notewave = nw
                        } else {
                            notewave = rendnote.notewave()
                            self.notewaveDic[nwid] = notewave
                        }
                        
                        self.memowaves[rendnote.id]
                            = Memowave(startSec: startSec,
                                       releaseSec: startSec + length,
                                       endSec: startSec + durSec,
                                       fq: rendnote.fq,
                                       volumeSmp: rendnote.volumeSmp,
                                       pan: rendnote.pan,
                                       envelopeMemo: rendnote.envelopeMemo,
                                       pitbend: rendnote.pitbend,
                                       notewave: notewave)
                        self.phases[rendnote.id] = 0
                    } else if let memowave = self.memowaves[rendnote.id], !rendnote.secRange.end.isInfinite,
                              memowave.endSec == nil {
                        
                        self.memowaves[rendnote.id]?.releaseSec = startSec + length
                        self.memowaves[rendnote.id]?.endSec = startSec + durSec
                    }
                }
            }
            
            for (id, memowave) in self.memowaves {
                if let endSec = memowave.endSec,
                    sec < memowave.startSec || sec >= endSec {
                    
                    self.memowaves[id] = nil
                    self.phases[id] = nil
                }
            }
            
            guard !self.memowaves.isEmpty else {
                isSilence.pointee = true
                return noErr
            }
            
            let framess = outputBLP.count.range.map {
                outputBLP[$0].mData!.assumingMemoryBound(to: Float.self)
            }
            
            let memowaves = self.memowaves
            var phases = self.phases
            for (id, memowave) in memowaves {
                var phase = phases[id]!
                let notewave = memowave.notewave
                let envelopeMemo = memowave.envelopeMemo
                let pitbend = memowave.pitbend
                guard notewave.samples.count >= 4 else { continue }
                let count = Double(notewave.samples.count)
                if !notewave.isLoop && phase >= count { continue }
                phase = phase.loop(0 ..< count)
                
                for i in 0 ..< Int(frameCount) {
                    let nSec = Double(i) * rSampleRate + sec
                    guard nSec >= memowave.startSec else { continue }
                    let envelopeSmp = envelopeMemo
                        .volumeSmp(atSec: nSec - memowave.startSec,
                                   releaseStartSec: memowave.releaseSec != nil ? memowave.releaseSec! - memowave.startSec : nil)
                    let loudnessScale = Loudness.reverseScale40Phon(fromFq: memowave.fq * pitbend.fqScale(atSec: nSec - memowave.startSec))
                    let nVolumeAmp, pan: Double
                    if pitbend.isEmpty {
                        nVolumeAmp = Volume(smp: memowave.volumeSmp * envelopeSmp * loudnessScale).amp
                        pan = memowave.pan
                    } else {
                        let stereo = pitbend.stereo(atSec: nSec - memowave.startSec)
                        nVolumeAmp = Volume(smp: memowave.volumeSmp * envelopeSmp * stereo.smp * loudnessScale).amp
                        pan = memowave.pan + stereo.pan
                    }
                    
                    let nv = notewave
                        .sample(at: i,
                                sec: nSec - memowave.startSec,
                                volumeAmp: nVolumeAmp,
                                from: envelopeMemo,
                                atPhase: &phase)
                    
                    if pan == 0 || framess.count < 2 {
                        let fnv = Float(nv)
                        for frames in framess {
                            frames[i] += fnv
                        }
                    } else {
                        let nPan = pan.clipped(min: -1, max: 1) * 0.75
                        if nPan < 0 {
                            framess[0][i] += Float(nv)
                            framess[1][i] += Float(nv * Volume(smp: 1 + nPan).amp)
                        } else {
                            framess[0][i] += Float(nv * Volume(smp: 1 - nPan).amp)
                            framess[1][i] += Float(nv)
                        }
                    }
                }
                
                phases[id] = phase
            }
            self.phases = phases
            
            return noErr
        }
        if volumeAmp != 1 {
            node.volume = Float(volumeAmp)
        }
        if pan != 0 {
            node.pan = Float(pan)
        }
        
        updateRendnotes()
    }
}

final class Sequencer {
    let pcmNodes: [(node: AVAudioSourceNode, reverbNode: AVAudioUnitReverb)]
    let pcmNoders: [UUID: AVAudioPCMNoder]
    private(set) var scoreNodes: [(node: AVAudioSourceNode, reverbNode: AVAudioUnitReverb)]
    private(set) var scoreNoders: [UUID: AVAudioScoreNoder]
    private(set) var mixings: [UUID: AVAudioMixing]
    private(set) var allMainNodes: [AVAudioNode]
    private(set) var allReverbNodes: [AVAudioUnitReverb]
    private(set) var reverbs: [UUID: AVAudioUnitReverb]
    let mixerNode: AVAudioMixerNode
    let limiterNode: AVAudioUnitEffect
    let engine: AVAudioEngine
    
    fileprivate var startTime = 0.0, startHostTime: UInt64 = 0
    var isPlaying = false
    
    let secoundDuration: Double
    
    init?(audiotracks: [Audiotrack], isAsync: Bool, startSec: Double,
          perceptionDelaySec: Double = 0,
          clipHandler: ((Float) -> ())? = nil) {
        let audiotracks = audiotracks.filter { !$0.isEmpty }
        
        struct Track {
            var rendnotes: [Rendnote]
            var id: UUID
        }
        
        var pcmNodes = [(node: AVAudioSourceNode,
                         reverbNode: AVAudioUnitReverb)]()
        var pcmNoders = [UUID: AVAudioPCMNoder]()
        var mixings = [UUID: AVAudioMixing]()
        var allMainNodes = [AVAudioNode]()
        var reverbs = [UUID: AVAudioUnitReverb]()
        var allReverbNodes = [AVAudioUnitReverb]()
        
        var sSec = perceptionDelaySec
        var scoreNodes = [(node: AVAudioSourceNode, reverbNode: AVAudioUnitReverb)]()
        var scoreNoders = [UUID: AVAudioScoreNoder]()
        for audiotrack in audiotracks {
            let durSec = audiotrack.durSec
            guard durSec > 0 else { continue }
            for value in audiotrack.values {
                guard value.beatRange.length > 0 && value.beatRange.end > 0 else { continue }
                switch value {
                case .score(let score):
                    guard !score.notes.isEmpty else { continue }
                    let rendnotes = score.notes.sorted(by: { $0.beatRange.start < $1.beatRange.start }).map {
                        Rendnote(note: $0, score: score, startSec: sSec)
                    }
                    guard !rendnotes.isEmpty else { continue }
                    
                    let noder = AVAudioScoreNoder(rendnotes: rendnotes,
                                                  startSec: startSec,
                                                  isAsync: isAsync,
                                                  volumeAmp: 1, pan: 0)
                    
                    let reverbNode = AVAudioUnitReverb()
                    reverbNode.loadFactoryPreset(.mediumHall)
                    reverbNode.wetDryMix = Float(Audio.defaultReverb) * 100
                    reverbs[score.id] = reverbNode
                    
                    scoreNodes.append((noder.node, reverbNode))
                    
                    scoreNoders[score.id] = noder
                    mixings[score.id] = noder.node
                    allMainNodes.append(noder.node)
                    allReverbNodes.append(reverbNode)
                case .sound(let content):
                    guard content.type.isAudio,
                          let timeOption = content.timeOption,
                          let localBeatRange = content.localBeatRange,
                          let pcmBuffer = content.pcmBuffer else { continue }
                    let beatRange = timeOption.beatRange
                    let sBeat = beatRange.start + max(localBeatRange.start, 0)
                    let inSBeat = min(localBeatRange.start, 0)
                    let eBeat = beatRange.start + min(localBeatRange.end, beatRange.length)
                    let startSec = Double(timeOption.sec(fromBeat: sBeat)) + sSec
                    let contentStartSec = Double(timeOption.sec(fromBeat: inSBeat))
                    let durSec = Double(timeOption.sec(fromBeat: max(eBeat - sBeat, 0)))
                    let noder = AVAudioPCMNoder(pcmBuffer: pcmBuffer,
                                                startTime: startSec,
                                                contentStartTime: contentStartSec,
                                                duration: durSec,
                                                volumeAmp: content.volume.amp,
                                                pan: content.pan)
                    
                    let reverbNode = AVAudioUnitReverb()
                    reverbNode.loadFactoryPreset(.mediumHall)
                    reverbNode.wetDryMix = Float(Audio.defaultReverb) * 100
                    reverbs[content.id] = reverbNode
                    
                    pcmNodes.append((noder.node, reverbNode))
                    
                    pcmNoders[content.id] = noder
                    mixings[content.id] = noder.node
                    allMainNodes.append(noder.node)
                    allReverbNodes.append(reverbNode)
                }
            }
            
            sSec += Double(audiotrack.durSec)
        }
        
        let engine = AVAudioEngine()
        
        let mixerNode = AVAudioMixerNode()
        engine.attach(mixerNode)
        self.mixerNode = mixerNode
        
        secoundDuration = sSec
        
        for (node, reverbNode) in pcmNodes {
            engine.attach(node)
            engine.attach(reverbNode)
            engine.connect(node,
                           to: reverbNode,
                           format: node.outputFormat(forBus: 0))
            engine.connect(reverbNode,
                           to: mixerNode,
                           format: reverbNode.outputFormat(forBus: 0))
        }
        self.pcmNodes = pcmNodes
        self.pcmNoders = pcmNoders
        
        for (node, reverbNode) in scoreNodes {
            engine.attach(node)
            engine.attach(reverbNode)
            engine.connect(node,
                           to: reverbNode,
                           format: node.outputFormat(forBus: 0))
            engine.connect(reverbNode,
                           to: mixerNode,
                           format: reverbNode.outputFormat(forBus: 0))
        }
        self.scoreNodes = scoreNodes
        self.scoreNoders = scoreNoders
        
        if let clipHandler {
            mixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, time in
                guard !buffer.isEmpty else { return }
                var peak: Float = 0.0
                for i in 0 ..< buffer.channelCount {
                    buffer.enumerated(channelIndex: i) { _, v in
                        let av = abs(v)
                        if av > peak {
                            peak = av
                        }
                    }
                }
                clipHandler(peak)
            }
        }
        
        let limiterNode = AVAudioUnitEffect.limiter()
        engine.attach(limiterNode)
        self.limiterNode = limiterNode
        
        engine.connect(mixerNode, to: limiterNode,
                       format: mixerNode.outputFormat(forBus: 0))
        engine.connect(limiterNode, to: engine.mainMixerNode,
                       format: limiterNode.outputFormat(forBus: 0))
        
        mixings.forEach {
            let v = $0.value.volume
            $0.value.volume = 0
            $0.value.volume = v
            let a = $0.value.pan
            $0.value.pan = 0
            $0.value.pan = a
        }
        
        self.engine = engine
        
        self.allMainNodes = allMainNodes
        self.allReverbNodes = allReverbNodes
        self.mixings = mixings
        self.reverbs = reverbs
        
        pcmNoders.forEach { $0.value.sequencer = self }
        scoreNoders.forEach { $0.value.sequencer = self }
    }
}
extension Sequencer {
    func append(_ noder: AVAudioScoreNoder, id: UUID) {
        let reverbNode = AVAudioUnitReverb()
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = Float(noder.reverb) * 100
        reverbs[id] = reverbNode
        
        scoreNodes.append((noder.node, reverbNode))
        scoreNoders[id] = noder
        mixings[id] = noder.node
        allMainNodes.append(noder.node)
        allReverbNodes.append(reverbNode)
        
        engine.attach(reverbNode)
        
        engine.attach(noder.node)
        engine.connect(noder.node,
                       to: reverbNode,
                       format: noder.node.outputFormat(forBus: 0))
        
        engine.connect(reverbNode,
                       to: mixerNode,
                       format: reverbNode.outputFormat(forBus: 0))
        
        noder.sequencer = self
    }
    
    var currentPositionInSec: Double {
        get {
            isPlaying ?
                AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime() - startHostTime) + startTime :
                startTime
        }
        set {
            startHostTime = AudioGetCurrentHostTime()
            startTime = newValue
        }
    }
    
    func startEngine() {
        if !engine.isRunning {
            try? engine.start()
        }
    }
    func stopEngine() {
        isPlaying = false
        if engine.isRunning {
            engine.stop()
        }
    }
    func endEngine() {
        engine.stop()
        engine.reset()
        
        for node in allMainNodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        for node in allReverbNodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        engine.disconnectNodeOutput(mixerNode)
        engine.detach(mixerNode)
        engine.disconnectNodeOutput(limiterNode)
        engine.detach(limiterNode)
    }
    func play() {
        startEngine()
        startHostTime = AudioGetCurrentHostTime()
        isPlaying = true
    }
    func stop() {
        isPlaying = false
    }
}
extension Sequencer {
    var clippingAudioUnit: ClippingAudioUnit {
        limiterNode.auAudioUnit as! ClippingAudioUnit
    }
    
    struct ExportError: Error {}
    
    func audio(sampleRate: Double,
               clippingAmp: Float? = Audio.floatClippingAmp,
               progressHandler: (Double, inout Bool) -> ()) throws -> Audio? {
        guard let buffer = try buffer(sampleRate: sampleRate,
                                      clippingAmp: clippingAmp,
                                      progressHandler: progressHandler) else { return nil }
        return Audio(pcmData: buffer.pcmData)
    }
    func buffer(sampleRate: Double,
                clippingAmp: Float? = Audio.floatClippingAmp,
                progressHandler: (Double, inout Bool) -> ()) throws -> AVAudioPCMBuffer? {
        let oldClippingAmp = clippingAudioUnit.clippingAmp
        clippingAudioUnit.clippingAmp = clippingAmp
        defer { clippingAudioUnit.clippingAmp = oldClippingAmp }
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 2,
                                         interleaved: true) else { throw ExportError() }
        try engine.enableManualRenderingMode(.offline,
                                             format: format,
                                             maximumFrameCount: 512)
        try engine.start()
        isPlaying = true
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            
            isPlaying = false
            endEngine()
            throw ExportError()
        }
        
        let length = AVAudioFramePosition(secoundDuration * sampleRate)
        
        guard let allBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                               frameCapacity: AVAudioFrameCount(length)) else {
            throw ExportError()
        }
        
        var stop = false
        while engine.manualRenderingSampleTime < length {
            do {
                let mrst = engine.manualRenderingSampleTime
                let frameCount = length - mrst
                let framesToRender = min(AVAudioFrameCount(frameCount), buffer.frameCapacity)
                let status = try engine.renderOffline(framesToRender, to: buffer)
                switch status {
                case .success:
                    if let ca = clippingAmp {
                        buffer.clip(amp: Float(ca))
                    }
                    
                    allBuffer.append(buffer)
                    progressHandler(Double(mrst) / Double(length), &stop)
                    if stop { return nil }
                case .insufficientDataFromInputNode:
                    throw ExportError()
                case .cannotDoInCurrentContext:
                    progressHandler(Double(mrst) / Double(length), &stop)
                    if stop { return nil }
                    Thread.sleep(forTimeInterval: 0.1)
                case .error: throw ExportError()
                @unknown default: throw ExportError()
                }
            } catch {
                isPlaying = false
                endEngine()
                throw error
            }
        }
        
        isPlaying = false
        endEngine()
        
        return allBuffer
    }
    
    func export(url: URL,
                sampleRate: Double,
                isCompress: Bool = true,
                progressHandler: (Double, inout Bool) -> ()) throws {
        if isCompress {
            guard let oBuffer = try buffer(sampleRate: sampleRate,
                                           clippingAmp: nil,
                                           progressHandler: progressHandler) else { return }
            let file = try AVAudioFile(forWriting: url,
                                       settings: oBuffer.format.settings,
                                       commonFormat: oBuffer.format.commonFormat,
                                       interleaved: oBuffer.format.isInterleaved)
            oBuffer.compress(targetDb: -Audio.headroomDb)
            try file.write(from: oBuffer)
            return
        }
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 2,
                                         interleaved: true) else { throw ExportError() }

        try engine.enableManualRenderingMode(.offline,
                                             format: format,
                                             maximumFrameCount: 512)
        try engine.start()
        isPlaying = true
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {

            isPlaying = false
            endEngine()
            throw ExportError()
        }

        let file = try AVAudioFile(forWriting: url,
                                   settings: engine.manualRenderingFormat.settings,
                                   commonFormat: engine.manualRenderingFormat.commonFormat,
                                   interleaved: engine.manualRenderingFormat.isInterleaved)
        
        var stop = false
        let length = AVAudioFramePosition(secoundDuration * sampleRate)
        while engine.manualRenderingSampleTime < length {
            do {
                let mrst = engine.manualRenderingSampleTime
                let frameCount = length - mrst
                let framesToRender = min(AVAudioFrameCount(frameCount), buffer.frameCapacity)
                let status = try engine.renderOffline(framesToRender, to: buffer)
                switch status {
                case .success:
                    buffer.clip(amp: Float(Audio.floatClippingAmp))
                    
                    try file.write(from: buffer)
                    progressHandler(Double(mrst) / Double(length), &stop)
                    if stop { return }
                case .insufficientDataFromInputNode:
                    throw ExportError()
                case .cannotDoInCurrentContext:
                    progressHandler(Double(mrst) / Double(length), &stop)
                    if stop { return }
                    Thread.sleep(forTimeInterval: 0.1)
                case .error: throw ExportError()
                @unknown default: throw ExportError()
                }
            } catch {
                isPlaying = false
                endEngine()
                throw error
            }
        }
        
        isPlaying = false
        endEngine()
    }
}

typealias PCMBuffer = AVAudioPCMBuffer
extension AVAudioPCMBuffer {
    struct AVAudioPCMBufferError: Error {}
    
    static var pcmFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: Audio.defaultSampleRate, channels: 1, interleaved: true)
    }
    static var exportPcmFormat: AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: Audio.defaultExportSampleRate, channels: 2, interleaved: true)
    }
    
    convenience init?(pcmData: Data) {
        guard !pcmData.isEmpty,
              let format = AVAudioPCMBuffer.pcmFormat else { return nil }
        let desc = format.streamDescription.pointee
        let frameCapacity = UInt32(pcmData.count) / desc.mBytesPerFrame
        self.init(pcmFormat: format, frameCapacity: frameCapacity)
        frameLength = self.frameCapacity
        let audioBuffer = audioBufferList.pointee.mBuffers
        pcmData.withUnsafeBytes { ptr in
            guard let address = ptr.baseAddress else { return }
            audioBuffer.mData?.copyMemory(from: address,
                                          byteCount: Int(audioBuffer.mDataByteSize))
        }
    }
    
    func convertDefaultFormat(isExportFormat: Bool = false) throws -> AVAudioPCMBuffer {
        guard let pcmFormat = isExportFormat ? AVAudioPCMBuffer.exportPcmFormat : AVAudioPCMBuffer.pcmFormat,
              let converter = AVAudioConverter(from: format,
                                               to: pcmFormat) else { throw AVAudioPCMBufferError() }
        let tl = Double(frameLength) / format.sampleRate
        let frameLength = AVAudioFrameCount(tl * pcmFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat,
                                            frameCapacity: frameLength) else { throw AVAudioPCMBufferError() }
        buffer.frameLength = frameLength
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return self
        }
        var error : NSError?
        let status = converter.convert(to: buffer, error: &error,
                                       withInputFrom: inputBlock)
        guard status != .error else { throw error ?? AVAudioPCMBufferError() }
        return buffer
    }
    
    var pcmData: Data {
        let audioBuffer = audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!,
                    count: Int(audioBuffer.mDataByteSize))
    }
    
    func segment(startingFrame: AVAudioFramePosition,
                 frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let nBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else { return nil }
        let bpf = format.streamDescription.pointee.mBytesPerFrame
        let abl = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let nabl = UnsafeMutableAudioBufferListPointer(nBuffer.mutableAudioBufferList)
        for (old, new) in zip(abl, nabl) {
            memcpy(new.mData,
                   old.mData?.advanced(by: Int(startingFrame) * Int(bpf)),
                   Int(frameCount) * Int(bpf))
        }
        nBuffer.frameLength = frameCount
        return nBuffer
    }
    
    var cmSampleBuffer: CMSampleBuffer? {
        let audioBufferList = mutableAudioBufferList
        let asbd = format.streamDescription
        var format: CMFormatDescription? = nil
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                    asbd: asbd,
                                                    layoutSize: 0,
                                                    layout: nil,
                                                    magicCookieSize: 0,
                                                    magicCookie: nil,
                                                    extensions: nil,
                                                    formatDescriptionOut: &format)
        guard status == noErr else { return nil }
        
        let ts = CMTimeScale(asbd.pointee.mSampleRate)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: ts),
                                        presentationTimeStamp: CMTime.zero,
                                        decodeTimeStamp: CMTime.invalid)
        var sampleBuffer: CMSampleBuffer? = nil
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                      dataBuffer: nil,
                                      dataReady: false,
                                      makeDataReadyCallback: nil,
                                      refcon: nil,
                                      formatDescription: format,
                                      sampleCount: CMItemCount(frameLength),
                                      sampleTimingEntryCount: 1,
                                      sampleTimingArray: &timing,
                                      sampleSizeEntryCount: 0,
                                      sampleSizeArray: nil,
                                      sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer = sampleBuffer else { return nil }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer,
                                                                blockBufferAllocator: kCFAllocatorDefault,
                                                                blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                flags: 0,
                                                                bufferList: audioBufferList)
        guard status == noErr else { return nil }
        return sampleBuffer
    }
    
    static func from(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        
        let afCount = AVAudioFrameCount(file.length)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: afCount) else { throw AVAudioPCMBufferError() }
        try file.read(into: buffer)
        return buffer
    }
    
    func append(_ buffer: AVAudioPCMBuffer) {
        guard format == buffer.format,
              frameLength + buffer.frameLength <= frameCapacity else {
            fatalError()
        }
        let dst = floatChannelData!
        let src = buffer.floatChannelData!
        memcpy(dst.pointee.advanced(by: stride * Int(frameLength)),
               src.pointee.advanced(by: buffer.stride * Int(0)),
               buffer.stride * Int(buffer.frameLength) * MemoryLayout<Float>.size)
        frameLength += buffer.frameLength
    }
    
    var sampleRate: Double {
        format.sampleRate
    }
    var channelCount: Int {
        Int(format.channelCount)
    }
    var frameCount: Int {
        Int(frameLength)
    }
    var secondsDuration: Double {
        Double(frameLength) / format.sampleRate
    }
    var isEmpty: Bool {
        floatChannelData == nil || frameLength == 0 || channelCount == 0
    }
    subscript(ci: Int, i: Int) -> Float {
        get { floatChannelData![ci][i * stride] }
        set { floatChannelData![ci][i * stride] = newValue }
    }
    func enumerated(channelIndex ci: Int, _ handler: (Int, Float) throws -> ()) rethrows {
        guard let samples = floatChannelData?[ci] else { return }
        for i in 0 ..< frameCount {
            try handler(i, samples[i * stride])
        }
    }
    
    func channelAmpsFromFloat(at ci: Int) -> [Double] {
        frameCount.range.map { Double(self[ci, $0]) }
    }
    
    subscript(i: Int) -> Double {
        get { doubleChannelData![i * stride] }
        set { doubleChannelData![i * stride] = newValue }
    }
    var doubleChannelData: UnsafeMutablePointer<Double>? {
        audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Double.self)
    }
    func enumeratedDouble(_ handler: (Int, Double) throws -> ()) rethrows {
        guard let samples = doubleChannelData else { return }
        for i in 0 ..< frameCount {
            try handler(i, samples[i * stride])
        }
    }
    
    func isOver(amp: Float) -> Bool {
        for ci in 0 ..< channelCount {
            for i in 0 ..< frameCount {
                if abs(self[ci, i]) > amp {
                    return true
                }
            }
        }
        return false
    }
    func clip(amp: Float) {
        for ci in 0 ..< channelCount {
            enumerated(channelIndex: ci) { i, v in
                if abs(v) > amp {
                    self[ci, i] = v < amp ? -amp : amp
                    print("clip", v)
                }
            }
        }
    }
    var doubleData: [[Double]] {
        get {
            var ns = Array(repeating: Array(repeating: 0.0,
                                            count: frameCount),
                           count: channelCount)
            if format.commonFormat == .pcmFormatFloat64 {
                for ci in 0 ..< channelCount {
                    enumeratedDouble() { i, v in
                        ns[ci][i] = v
                    }
                }
                return ns
            } else {
                for ci in 0 ..< channelCount {
                    enumerated(channelIndex: ci) { i, v in
                        ns[ci][i] = Double(v)
                    }
                }
                return ns
            }
        }
        set {
            if format.commonFormat == .pcmFormatFloat64 {
                for ci in 0 ..< channelCount {
                    enumeratedDouble() { i, v in
                        self[i] = newValue[ci][i]
                    }
                }
            } else {
                for ci in 0 ..< channelCount {
                    enumerated(channelIndex: ci) { i, v in
                        self[ci, i] = Float(newValue[ci][i])
                    }
                }
            }
        }
    }
    
    var samplePeakDb: Double {
        var peak = 0.0
        for ci in 0 ..< channelCount {
            enumerated(channelIndex: ci) { _, v in
                peak = max(abs(Double(v)), peak)
            }
        }
        return Volume(amp: peak).db
    }
    var  integratedLoudness: Double {
        let loudness = Loudness(sampleRate: sampleRate)
        return (try? loudness.integratedLoudness(data: doubleData)) ?? 0
    }
    func normalizePeak(target: Double) {
        let gain = Loudness.normalizePeakScale(data: doubleData,
                                               target: target)
        self *= Float(gain)
        print("Peak Scale: \(gain) \(integratedLoudness) LUFS")
    }
    func normalizeLoudness(targetLoudness: Double) {
        let gain = Loudness.normalizeLoudnessScale(inputLoudness: integratedLoudness,
                                                   targetLoudness: targetLoudness)
        self *= Float(gain)
        print("Loudness Scale: \(gain) \(integratedLoudness) LUFS")
    }
    
    static func *= (lhs: PCMBuffer, rhs: Float) {
        var rhs = rhs
        for ci in 0 ..< lhs.channelCount {
            let data = lhs.floatChannelData![ci]
            vDSP_vsmul(data, lhs.stride,
                       &rhs,
                       data, lhs.stride, vDSP_Length(lhs.frameLength))
        }
    }
    
    func compress(targetDb: Double,
                  attack: Double = 0.02, release: Double = 0.02) {
        struct P {
            var minI, maxI: Int, scale: Float
        }
        let targetAmp = Float(Volume(db: targetDb).amp)
        
        var minI: Int?, maxDAmp: Float = 0.0, ps = [P]()
        for i in 0 ..< frameCount {
            var maxAmp: Float = 0.0
            for ci in 0 ..< channelCount {
                let amp = self[ci, i]
                maxAmp = max(maxAmp, abs(amp))
            }
            if maxAmp > targetAmp {
                if minI == nil {
                    minI = i
                }
                maxDAmp = max(maxDAmp, maxAmp - targetAmp)
            } else {
                if let nMinI = minI {
                    ps.append(P(minI: nMinI, maxI: i - 1, scale: targetAmp / (maxDAmp + targetAmp)))
                    minI = nil
                    maxDAmp = 0
                }
            }
        }
        let attackCount = Int(attack * sampleRate)
        let releaseCount = Int(release * sampleRate)
        var scales = [Float](repeating: 1, count: frameCount)
        for p in ps {
            let minI = max(0, p.minI - attackCount)
            for i in minI ..< p.minI {
                let t = Float(i - minI) / Float(attackCount)
                let scale = Float.linear(1, p.scale, t: t)
                scales[i] = min(scale, scales[i])
            }
            for i in p.minI ... p.maxI {
                scales[i] = p.scale
            }
            let maxI = min(frameCount - 1, p.maxI + releaseCount)
            if p.maxI + 1 <= maxI {
                for i in (p.maxI + 1) ... maxI {
                    let t = Float(i - p.maxI) / Float(releaseCount)
                    let scale = Float.linear(p.scale, 1, t: t)
                    scales[i] = min(scale, scales[i])
                }
            }
        }
        
        for ci in 0 ..< channelCount {
            enumerated(channelIndex: ci) { i, v in
                self[ci, i] *= scales[i]
            }
        }
    }
}

extension AVAudioUnitEffect {
    static func limiter() -> AVAudioUnitEffect {
        let cacd = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                            componentSubType: 0x666c7472,
                                            componentManufacturer: 0x12121213,
                                            componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
                                            componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(ClippingAudioUnit.self,
                                     as: cacd,
                                     name: "RasenClippingAudioUnit",
                                     version: 1)
        return AVAudioUnitEffect(audioComponentDescription: cacd)
    }
}
final class ClippingAudioUnit: AUAudioUnit {
    let inputBus: AUAudioUnitBus
    let outputBus: AUAudioUnitBus

    lazy private var inputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .input,
                            busses: [inputBus])
    }()
    public override var inputBusses: AUAudioUnitBusArray {
        inputBusArray
    }
    lazy private var outputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .output,
                            busses: [outputBus])
    }()
    public override var outputBusses: AUAudioUnitBusArray {
        outputBusArray
    }

    private var maxFramesToRender: UInt32 = 512
    private var pcmBuffer: AVAudioPCMBuffer?

    var clippingAmp: Float? = Float(Audio.floatClippingAmp)
    
    struct SError: Error {}

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100,
                                         channels: 2) else { throw SError() }
        try inputBus = AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 8
        try outputBus = AUAudioUnitBus(format: format)

        guard let pcmBuffer
                = AVAudioPCMBuffer(pcmFormat: format,
                                   frameCapacity: maxFramesToRender) else { throw SError() }
        self.pcmBuffer = pcmBuffer

        try super.init(componentDescription: componentDescription,
                       options: options)

        self.maximumFramesToRender = maxFramesToRender
    }
    override func allocateRenderResources() throws {
        try super.allocateRenderResources()

        guard let pcmBuffer
                = AVAudioPCMBuffer(pcmFormat: inputBus.format,
                                   frameCapacity: maxFramesToRender) else { throw SError() }
        self.pcmBuffer = pcmBuffer
    }
    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        self.pcmBuffer = nil
    }

    public override var canProcessInPlace: Bool { true }

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] (actionFlags, timestamp, frameCount, outputBusNumber,
                              outputData, realtimeEventListHead, pullInputBlock) in
            guard let au = self else { return kAudioUnitErr_NoConnection }
            guard frameCount <= au.maximumFramesToRender else {
                return kAudioUnitErr_TooManyFramesToProcess
            }
            guard pullInputBlock != nil else {
                return kAudioUnitErr_NoConnection
            }
            
            guard let inputData = au.pcmBuffer?.mutableAudioBufferList else { return kAudioUnitErr_NoConnection }
            let inputBLP = UnsafeMutableAudioBufferListPointer(inputData)
            let byteSize = Int(min(frameCount, au.maxFramesToRender)) * MemoryLayout<Float>.size
            for i in 0 ..< inputBLP.count {
                inputBLP[i].mDataByteSize = UInt32(byteSize)
            }
            
            var pullFlags = AudioUnitRenderActionFlags(rawValue: 0)
            let err = pullInputBlock?(&pullFlags, timestamp, frameCount, 0, inputData)
            if let err = err, err != noErr { return err }

            let outputBLP = UnsafeMutableAudioBufferListPointer(outputData)
            for i in 0 ..< outputBLP.count {
                outputBLP[i].mNumberChannels = inputBLP[i].mNumberChannels
                outputBLP[i].mDataByteSize = inputBLP[i].mDataByteSize
               if outputBLP[i].mData == nil {
                  outputBLP[i].mData = inputBLP[i].mData
               }
            }
            guard !outputBLP.isEmpty else { return noErr }
            
            if let clippingAmp = au.clippingAmp {
                for i in 0 ..< outputBLP.count {
                    let inputFrames = inputBLP[i].mData!.assumingMemoryBound(to: Float.self)
                    let outputFrames = outputBLP[i].mData!.assumingMemoryBound(to: Float.self)
                    for i in 0 ..< Int(frameCount) {
                        outputFrames[i] = inputFrames[i]
                        if outputFrames[i].isNaN {
                            outputFrames[i] = 0
                            print("nan")
                        } else if outputFrames[i] < -clippingAmp {
                            outputFrames[i] = -clippingAmp
                        } else if outputFrames[i] > clippingAmp {
                            outputFrames[i] = clippingAmp
                        }
                    }
                }
            } else {
                for i in 0 ..< outputBLP.count {
                    let inputFrames = inputBLP[i].mData!.assumingMemoryBound(to: Float.self)
                    let outputFrames = outputBLP[i].mData!.assumingMemoryBound(to: Float.self)
                    for i in 0 ..< Int(frameCount) {
                        outputFrames[i] = inputFrames[i]
                    }
                }
            }
            
            return noErr
        }
    }
}

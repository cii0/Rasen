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

import RealModule

extension Score {
    static func rendnotes(from score: Score, _ timeframe: Timeframe,
                          position: Point,
                          startSecDur: Double,
                          sampleRate: Double = Audio.defaultSampleRate,
                          isUsingFirst: Bool,
                          isUsingLast: Bool) -> [Rendnote] {
        let preBeat = timeframe.beatRange.start
        let nextBeat = timeframe.beatRange.end
        var notes: [Note] = score.notes.sorted { $0.beatRange.start < $1.beatRange.start }.compactMap { note in
            guard score.pitchRange.contains(note.pitch) else { return nil }
            var note = score.convertPitchToWorld(note)
            note.beatRange.start += preBeat + timeframe.localStartBeat
            guard note.beatRange.length > 0
                    && note.beatRange.end > preBeat
                    && note.beatRange.start < nextBeat
                    && note.volumeAmp >= Volume.minAmp
                    && note.volumeAmp <= Volume.maxAmp else {
                return nil
            }
            if note.beatRange.start < preBeat {
                note.beatRange.length -= preBeat - note.beatRange.start
                note.beatRange.start = preBeat
            }
            if note.beatRange.end > nextBeat {
                note.beatRange.end = nextBeat
            }
            
            note.volumeAmp = note.volumeAmp
                .clipped(min: Volume.minAmp, max: Volume.maxAmp)
            return note
        }
        
        let sourceFIlter = SourceFilter(score.tone.spectlope)
        guard score.isVoice else {
            return notes.map { note in
                let startBeat = note.beatRange.start
                let endBeat = note.beatRange.end
                let snapBeat = startBeat.interval(scale: Rational(1, 4))
                let sSec = Double(timeframe.sec(fromBeat: startBeat)) + startSecDur
                let eSec = Double(timeframe.sec(fromBeat: endBeat)) + startSecDur
                let snapSec = Double(timeframe.sec(fromBeat: snapBeat)) + startSecDur
                let dSec = sSec - snapSec
                
                let pitbend = note.pitbend.with(scale: eSec - sSec)
                return .init(fq: note.fq,
                             sourceFilter: sourceFIlter,
                             spectlopeInterpolation: nil,
                             deltaSpectlopeInterpolation: nil,
                             fAlpha: 1,
                             seed: Rendnote.seed(fromFq: note.fq, sec: sSec,
                                                 position: position),
                             overtone: score.tone.overtone,
                             pitbend: pitbend,
                             secRange: sSec ..< eSec,
                             startDeltaSec: dSec,
                             volumeAmp: note.volumeAmp,
                             waver: .init(score.tone, pitbend: pitbend),
                             tempo: Double(timeframe.tempo),
                             sampleRate: sampleRate,
                             dftCount: Audio.defaultDftCount)
            }
        }
        
        var ivs = [IndexValue<Note>]()
        for (ni, note) in notes.enumerated().reversed() {
            if note.isBreath {
                if note.beatRange.length <= Rational(1, 2) {
                    notes[ni].beatRange.length /= 2
                } else {
                    let isBreath = note.beatRange.length >= 1
                    let eSec = notes[ni].beatRange.end
                    let sSec = eSec - Rational(1, 4)
                    notes[ni].beatRange.length -= Rational(1, 2)
                    notes[ni].isBreath = false
                    let tNote = Note(pitch: note.pitch,
                                     beatRange: sSec ..< eSec,
                                     lyric: isBreath ? "^" : "っ",
                                     isBreath: true)
                    ivs.append(IndexValue(value: tNote, index: ni + 1))
                }
            }
        }
        if !ivs.isEmpty {
            notes.insert(ivs)
        }
        
        var noteSecTuples = [(secRange: Range<Double>, dSec: Double)]()
        noteSecTuples.reserveCapacity(notes.count)
        for note in notes {
            let startBeat = note.beatRange.start
            let endBeat = note.beatRange.end
            let snapBeat = startBeat.interval(scale: Rational(1, 4))
            let sSec = Double(timeframe.sec(fromBeat: startBeat)) + startSecDur
            let eSec = Double(timeframe.sec(fromBeat: endBeat)) + startSecDur
            let snapSec = Double(timeframe.sec(fromBeat: snapBeat)) + startSecDur
            let dSec = sSec - snapSec
            noteSecTuples.append((sSec ..< eSec, dSec))
        }
        
        let tempo = Double(timeframe.tempo)
        
        var nNotes = [Rendnote]()
        nNotes.reserveCapacity(notes.count)
        var previousMora: Mora?
        for (ni, note) in notes.enumerated() {
            let deltaSecToNext: Double, nextMora: Mora?
            if ni + 1 < notes.count {
                let nextNote = notes[ni + 1]
                let dstn = noteSecTuples[ni + 1].secRange.start - noteSecTuples[ni].secRange.end
                let fq = nextNote.fq
                if dstn == 0, !note.isBreath,
                   let aNextMora = Mora(hiragana: nextNote.lyric,
                                        fq: fq,
                                        previousMora: nil,
                                        nextMora: nil,
                                        isVowelReduction: note.isVowelReduction,
                                        from: score.tone.spectlope) {
                    deltaSecToNext = dstn
                        + aNextMora.deltaSyllabicStartSec
                        - aNextMora.onsetSecDur
                    nextMora = aNextMora
                } else {
                    deltaSecToNext = dstn
                    nextMora = nil
                }
            } else {
                deltaSecToNext = .infinity
                nextMora = nil
            }
            
            let fq = note.fq
            guard let mora = Mora(hiragana: note.lyric,
                                  fq: fq,
                                  previousMora: previousMora,
                                  nextMora: nextMora,
                                  isVowelReduction: note.isVowelReduction,
                                  from: score.tone.spectlope) else {
                previousMora = nil
                continue
            }
            
            guard mora.syllabics != [.sokuon]
                    && !(ni == 0 && !isUsingFirst)
                    && !(ni == notes.count - 1 && !isUsingLast) else {
                previousMora = nextMora != nil ? mora : nil
                continue
            }
            
            let fDeltaSec = previousMora == nil ? 0.0065 : 0
            let dssSec = mora.deltaSyllabicStartSec + fDeltaSec
            let dSec = noteSecTuples[ni].dSec
            let snapSSec = noteSecTuples[ni].secRange.start - dSec
            let mainSec = noteSecTuples[ni].secRange.start + dssSec
            
            for onset in mora.onsets.reversed() {
                let oDur = onset.duration
                let aDur = -oDur + onset.sec
                let nsSec = mainSec + aDur
                let neSec = nsSec + oDur
                
                let envelope = Envelope(attack: onset.attackSec,
                                        decay: 0, sustain: 1,
                                        release: onset.releaseSec)
                let waver = Waver(envelope: envelope)
                let volumeAmp = note.volumeAmp * onset.volumeAmp
                nNotes.append(.init(fq: fq,
                                    sourceFilter: onset.sourceFilter,
                                    spectlopeInterpolation: nil,
                                    deltaSpectlopeInterpolation: nil,
                                    fAlpha: 1,
                                    seed: Rendnote.seed(fromFq: fq,
                                                        sec: nsSec,
                                                        position: position),
                                    overtone: score.tone.overtone,
                                    pitbend: .init(),
                                    secRange: nsSec ..< neSec,
                                    startDeltaSec: nsSec - snapSSec,
                                    volumeAmp: volumeAmp,
                                    waver: waver,
                                    tempo: tempo,
                                    sampleRate: sampleRate,
                                    dftCount: Audio.defaultDftCount))
            }
            
            if !note.isVowelReduction {
                let eSec = noteSecTuples[ni].secRange.end
                let attackSec = score.tone.envelope.attack,
                    decaySec = score.tone.envelope.decay,
                    sustainSec = score.tone.envelope.sustain
                let minReleaseSec = 0.04
                let maxReleaseSec = max(minReleaseSec,
                                        score.tone.envelope.release)
                let releaseSec = deltaSecToNext.clipped(min: minReleaseSec,
                                                        max: maxReleaseSec)
                
                let nsSec = mainSec + mora.deltaSinStartSec
                let neSec = nextMora?.isOffVoice ?? false ?
                    eSec
                    + min(0, deltaSecToNext - releaseSec)
                    + releaseSec * 0.25 :
                    eSec - releaseSec * 0.25
                let nDur = neSec - nsSec
                
                let envelope = Envelope(attack: attackSec,
                                        decay: decaySec,
                                        sustain: sustainSec,
                                        release: releaseSec)
                let pitbend = (note.pitbend.isEmpty ?
                    Pitbend(isVibrato: note.isVibrato,
                            duration: nDur,
                            fq: fq,
                            isVowel: mora.isVowel,
                            previousFq: previousMora?.fq,
                            nextFq: nextMora?.fq) :
                                note.pitbend)
                    .with(scale: nDur)
                let waver = Waver(envelope: envelope,
                                  firstPitchbend: score.tone.pitchbend,
                                  pitbend: pitbend)
                let si = mora.spectlopeInterpolation(fromDuration: nDur + releaseSec)
                let dsi = Interpolation(keys: si.keys.map {
                    .init(value: $0.value.divide(score.tone.spectlope),
                          time: $0.time, type: $0.type)
                }, duration: si.duration)
                nNotes.append(.init(fq: note.fq,
                                    sourceFilter: sourceFIlter,
                                    spectlopeInterpolation: si,
                                    deltaSpectlopeInterpolation: dsi,
                                    fAlpha: 1,
                                    seed: Rendnote.seed(fromFq: fq,
                                                        sec: mainSec,
                                                        position: position),
                                    overtone: score.tone.overtone,
                                    pitbend: pitbend,
                                    secRange: nsSec ..< neSec,
                                    startDeltaSec: nsSec - snapSSec,
                                    volumeAmp: note.volumeAmp,
                                    waver: waver,
                                    tempo: tempo,
                                    sampleRate: sampleRate,
                                    dftCount: Audio.defaultDftCount))
            }
            
            previousMora = nextMora != nil ? mora : nil
        }
        
        return nNotes
    }
}

struct Formant: Hashable, Codable {
    var sdFq = 0.0, sFq = 0.0, eFq = 0.0, edFq = 0.0,
        smp = 0.0, noiseT = 0.0, edSmp = 0.0, edNoiseT = 0.0
}
extension Formant: Protobuf {
    init(_ pb: PBFormant) throws {
        sdFq = max(0, ((try? pb.sdFq.notNaN()) ?? 0))
        sFq = max(0, ((try? pb.sFq.notNaN()) ?? 0))
        eFq = max(0, ((try? pb.eFq.notNaN()) ?? 0))
        edFq = max(0, ((try? pb.edFq.notNaN()) ?? 0))
        smp = Volume(amp: pb.amp.clipped(min: Volume.minAmp,
                                         max: Volume.maxAmp)).smp
        noiseT = ((try? pb.noiseT.notNaN()) ?? 0).clipped(min: 0, max: 1)
        edSmp = Volume(amp: pb.edAmp.clipped(min: Volume.minAmp,
                                             max: Volume.maxAmp)).smp
        edNoiseT = ((try? pb.edNoiseT.notNaN()) ?? 0).clipped(min: 0, max: 1)
        if sFq > eFq {
            let n = sFq
            sFq = eFq
            eFq = n
        }
    }
    var pb: PBFormant {
        .with {
            $0.sdFq = sdFq
            $0.sFq = sFq
            $0.eFq = eFq
            $0.edFq = edFq
            $0.amp = Volume(smp: smp).amp
            $0.noiseT = noiseT
            $0.edAmp = Volume(smp: edSmp).amp
            $0.edNoiseT = edNoiseT
        }
    }
}
extension Formant: Interpolatable {
    static func linear(_ f0: Self, _ f1: Self, t: Double) -> Self {
        .init(sdFq: .linear(f0.sdFq, f1.sdFq, t: t),
              sFq: .linear(f0.sFq, f1.sFq, t: t),
              eFq: .linear(f0.eFq, f1.eFq, t: t),
              edFq: .linear(f0.edFq, f1.edFq, t: t),
              smp: .linear(f0.smp, f1.smp, t: t),
              noiseT: .linear(f0.noiseT, f1.noiseT, t: t),
              edSmp: .linear(f0.edSmp, f1.edSmp, t: t),
              edNoiseT: .linear(f0.edNoiseT, f1.edNoiseT, t: t))
    }
    static func firstSpline(_ f1: Self, _ f2: Self, _ f3: Self,
                            t: Double) -> Self {
        .init(sdFq: .firstSpline(f1.sdFq, f2.sdFq, f3.sdFq, t: t),
              sFq: .firstSpline(f1.sFq, f2.sFq, f3.sFq, t: t),
              eFq: .firstSpline(f1.eFq, f2.eFq, f3.eFq, t: t),
              edFq: .firstSpline(f1.edFq, f2.edFq, f3.edFq, t: t),
              smp: .firstSpline(f1.smp, f2.smp, f3.smp, t: t),
              noiseT: .firstSpline(f1.noiseT, f2.noiseT, f3.noiseT, t: t),
              edSmp: .firstSpline(f1.edSmp, f2.edSmp, f3.edSmp, t: t),
              edNoiseT: .firstSpline(f1.edNoiseT, f2.edNoiseT, f3.edNoiseT, t: t))
    }
    static func spline(_ f0: Self, _ f1: Self,
                       _ f2: Self, _ f3: Self, t: Double) -> Self {
        .init(sdFq: .spline(f0.sdFq, f1.sdFq, f2.sdFq, f3.sdFq, t: t),
              sFq: .spline(f0.sFq, f1.sFq, f2.sFq, f3.sFq, t: t),
              eFq: .spline(f0.eFq, f1.eFq, f2.eFq, f3.eFq, t: t),
              edFq: .spline(f0.edFq, f1.edFq, f2.edFq, f3.edFq, t: t),
              smp: .spline(f0.smp, f1.smp, f2.smp, f3.smp, t: t),
              noiseT: .spline(f0.noiseT, f1.noiseT,
                               f2.noiseT, f3.noiseT, t: t),
              edSmp: .spline(f0.edSmp, f1.edSmp, f2.edSmp, f3.edSmp, t: t),
              edNoiseT: .spline(f0.edNoiseT, f1.edNoiseT,
                               f2.edNoiseT, f3.edNoiseT, t: t))
    }
    static func lastSpline(_ f0: Self, _ f1: Self, _ f2: Self,
                           t: Double) -> Self {
        .init(sdFq: .lastSpline(f0.sdFq, f1.sdFq, f2.sdFq, t: t),
              sFq: .lastSpline(f0.sFq, f1.sFq, f2.sFq, t: t),
              eFq: .lastSpline(f0.eFq, f1.eFq, f2.eFq, t: t),
              edFq: .lastSpline(f0.edFq, f1.edFq, f2.edFq, t: t),
              smp: .lastSpline(f0.smp, f1.smp, f2.smp, t: t),
              noiseT: .lastSpline(f0.noiseT, f1.noiseT, f2.noiseT, t: t),
              edSmp: .lastSpline(f0.edSmp, f1.edSmp, f2.edSmp, t: t),
              edNoiseT: .lastSpline(f0.edNoiseT, f1.edNoiseT, f2.edNoiseT, t: t))
    }
}
extension Formant: MonoInterpolatable {
    static func firstMonospline(_ f1: Self, _ f2: Self, _ f3: Self,
                                with ms: Monospline) -> Self {
        .init(sdFq: .firstMonospline(f1.sdFq, f2.sdFq, f3.sdFq, with: ms),
              sFq: .firstMonospline(f1.sFq, f2.sFq, f3.sFq, with: ms),
              eFq: .firstMonospline(f1.eFq, f2.eFq, f3.eFq, with: ms),
              edFq: .firstMonospline(f1.edFq, f2.edFq, f3.edFq, with: ms),
              smp: .firstMonospline(f1.smp, f2.smp, f3.smp, with: ms),
              noiseT: .firstMonospline(f1.noiseT, f2.noiseT, f3.noiseT, with: ms),
              edSmp: .firstMonospline(f1.edSmp, f2.edSmp, f3.edSmp, with: ms),
              edNoiseT: .firstMonospline(f1.edNoiseT, f2.edNoiseT, f3.edNoiseT, with: ms))
    }
    static func monospline(_ f0: Self, _ f1: Self, _ f2: Self,
                           _ f3: Self, with ms: Monospline) -> Self {
        .init(sdFq: .monospline(f0.sdFq, f1.sdFq, f2.sdFq, f3.sdFq, with: ms),
              sFq: .monospline(f0.sFq, f1.sFq, f2.sFq, f3.sFq, with: ms),
              eFq: .monospline(f0.eFq, f1.eFq, f2.eFq, f3.eFq, with: ms),
              edFq: .monospline(f0.edFq, f1.edFq, f2.edFq, f3.edFq, with: ms),
              smp: .monospline(f0.smp, f1.smp, f2.smp, f3.smp, with: ms),
              noiseT: .monospline(f0.noiseT, f1.noiseT,
                                   f2.noiseT, f3.noiseT, with: ms),
              edSmp: .monospline(f0.edSmp, f1.edSmp, f2.edSmp, f3.edSmp, with: ms),
              edNoiseT: .monospline(f0.edNoiseT, f1.edNoiseT,
                                   f2.edNoiseT, f3.edNoiseT, with: ms))
    }
    static func lastMonospline(_ f0: Self, _ f1: Self,
                               _ f2: Self, with ms: Monospline) -> Self {
        .init(sdFq: .lastMonospline(f0.sdFq, f1.sdFq, f2.sdFq, with: ms),
              sFq: .lastMonospline(f0.sFq, f1.sFq, f2.sFq, with: ms),
              eFq: .lastMonospline(f0.eFq, f1.eFq, f2.eFq, with: ms),
              edFq: .lastMonospline(f0.edFq, f1.edFq, f2.edFq, with: ms),
              smp: .lastMonospline(f0.smp, f1.smp, f2.smp, with: ms),
              noiseT: .lastMonospline(f0.noiseT, f1.noiseT, f2.noiseT, with: ms),
              edSmp: .lastMonospline(f0.edSmp, f1.edSmp, f2.edSmp, with: ms),
              edNoiseT: .lastMonospline(f0.edNoiseT, f1.edNoiseT, f2.edNoiseT, with: ms))
    }
}
extension Formant {
    var fq: Double {
        get { sFq.mid(eFq) }
        set {
            let dFq = dFq
            sFq = newValue - dFq
            eFq = newValue + dFq
        }
    }
    var fqRange: ClosedRange<Double> {
        get { sFq ... eFq }
        set {
            sFq = newValue.lowerBound
            eFq = newValue.upperBound
        }
    }
    var dFq: Double {
        get { (eFq - sFq) / 2 }
        set {
            let fq = fq
            sFq = fq - newValue
            eFq = fq + newValue
        }
    }
    var ssFq: Double {
        get { sFq - sdFq }
        set { sdFq = sFq - newValue }
    }
    var eeFq: Double {
        get { eFq + edFq }
        set { edFq = newValue - eFq }
    }
    
    var fqSmp: Point {
        .init(fq, smp)
    }
    var sFqSmp: Point {
        .init(sFq, smp)
    }
    var eFqSmp: Point {
        .init(eFq, smp)
    }
    var eeFqSmp: Point {
        .init(eeFq, edSmp)
    }
    var noiseSmp: Double {
        get { smp * noiseT }
        set { noiseT = (smp == 0 ? 0 : newValue / smp).clipped(min: 0, max: 1) }
    }
    var editNoiseSmp: Double {
        get { smp * noiseT * 0.75 }
        set { noiseT = (smp == 0 ? 0 : newValue / smp / 0.75).clipped(min: 0, max: 1) }
    }
    
    var fqNoiseT: Point {
        .init(fq, noiseT)
    }
    var fqNoiseSmp: Point {
        .init(fq, noiseSmp)
    }
    var editFqNoiseSmp: Point {
        .init(fq, editNoiseSmp)
    }
    var sFqNoiseT: Point {
        .init(sFq, noiseT)
    }
    var sFqNoiseSmp: Point {
        .init(sFq, noiseSmp)
    }
    var eFqNoiseT: Point {
        .init(eFq, noiseT)
    }
    var eFqNoiseSmp: Point {
        .init(eFq, noiseSmp)
    }
    var edNoiseSmp: Double {
        get { edSmp * edNoiseT }
        set { edNoiseT = (newValue / edSmp).clipped(min: 0, max: 1) }
    }
    var editEdNoiseSmp: Double {
        get { edSmp * edNoiseT * 0.75 }
        set { edNoiseT = (edSmp == 0 ? 0 : newValue / edSmp / 0.75).clipped(min: 0, max: 1) }
    }
    var eeFqNoiseT: Point {
        .init(eeFq, edNoiseT)
    }
    var eeFqNoiseSmp: Point {
        .init(eeFq, edNoiseSmp)
    }
    var editEeFqNoiseSmp: Point {
        .init(eeFq, editEdNoiseSmp)
    }
    
    mutating func formMultiplyFq(_ x: Double) {
        sdFq *= x
        sFq *= x
        eFq *= x
        edFq *= x
    }
    func multiplyFq(_ x: Double) -> Self {
        var n = self
        n.formMultiplyFq(x)
        return n
    }
    
    mutating func formMultiplySmp(_ x: Double) {
        smp *= x
        edSmp *= x
    }
    func multiplySmp(_ x: Double) -> Self {
        var n = self
        n.formMultiplySmp(x)
        return n
    }
    
    mutating func fillSmp(_ other: Self) {
        smp = other.smp
        edSmp = other.edSmp
    }
    func filledSmp(_ other: Self) -> Self {
        var n = self
        n.fillSmp(other)
        return n
    }
    
    mutating func fillNoiseT(_ other: Self) {
        noiseT = other.noiseT
        edNoiseT = other.edNoiseT
    }
    func filledNoiseT(_ other: Self) -> Self {
        var n = self
        n.fillNoiseT(other)
        return n
    }
    
    mutating func formToNoise() {
        noiseT = 1
        edNoiseT = 1
    }
    func toNoise() -> Self {
        var n = self
        n.formToNoise()
        return n
    }
    
    var isFullNoise: Bool {
        noiseT == 1 && edNoiseT == 1
    }
}

struct Spectlope: Hashable, Codable {
    var formants: [Formant] = [
        .init(sFq: 0, eFq: 300, edFq: 400,
              smp: 0.8, noiseT: 0,
              edSmp: 0.65, edNoiseT: 0.1),
        .init(sdFq: 400, sFq: 850, eFq: 1109, edFq: 400,
              smp: 1, noiseT: 0.3,
              edSmp: 0.7, edNoiseT: 0.1),
        .init(sdFq: 400, sFq: 1700, eFq: 2050, edFq: 400,
              smp: 1, noiseT: 0.5,
              edSmp: 0.53, edNoiseT: 0.1),
        .init(sdFq: 400, sFq: 3700, eFq: 3900, edFq: 400,
              smp: 0.82, noiseT: 0.6,
              edSmp: 0.4, edNoiseT: 0.2),
        .init(sdFq: 400, sFq: 5200, eFq: 5500, edFq: 400,
              smp: 0.7, noiseT: 0.6,
              edSmp: 0.1, edNoiseT: 0.3),
        .init(sdFq: 400, sFq: 6700, eFq: 7100, edFq: 400,
              smp: 0.3, noiseT: 0.7,
              edSmp: 0.1, edNoiseT: 0.45),
        .init(sdFq: 500, sFq: 8500, eFq: 9100, edFq: 500,
              smp: 0.4, noiseT: 0.7,
              edSmp: 0.1, edNoiseT: 0.7),
        .init(sdFq: 600, sFq: 11000, eFq: 11500, edFq: 600,
              smp: 0.3, noiseT: 0.75,
              edSmp: 0.1, edNoiseT: 0.8)
    ]
}
extension Spectlope: Protobuf {
    init(_ pb: PBSpectlope) throws {
        formants = pb.formants.compactMap { try? Formant($0) }
    }
    var pb: PBSpectlope {
        .with {
            $0.formants = formants.map { $0.pb }
        }
    }
}
enum SpectlopeType {
    case fqSmp, fqNoiseSmp, editFqNoiseSmp, dFqZero,
         ssFqSmp, ssFqNoiseSmp, editSsFqNoiseSmp,
         eeFqSmp, eeFqNoiseSmp, editEeFqNoiseSmp
}
extension Spectlope {
    static let empty = Self.init(formants: .init(repeating: .init(),
                                                 count: 8))
    subscript(i: Int, type: SpectlopeType) -> Point {
        get {
            switch type {
            case .fqSmp: .init(self[i].fqSmp)
            case .fqNoiseSmp: .init(self[i].fqNoiseSmp)
            case .editFqNoiseSmp: .init(self[i].editFqNoiseSmp)
            case .dFqZero: .init(self[i].dFq, 0)
            case .ssFqSmp: .init(self[i].ssFq, self[i - 1].edSmp)
            case .ssFqNoiseSmp: .init(self[i].ssFq, 
                                      self[i - 1].edNoiseSmp)
            case .editSsFqNoiseSmp: .init(self[i].ssFq,
                                          self[i - 1].editEdNoiseSmp)
            case .eeFqSmp: .init(self[i].eeFq, self[i].edSmp)
            case .eeFqNoiseSmp: .init(self[i].eeFq,
                                      self[i].edNoiseSmp)
            case .editEeFqNoiseSmp: .init(self[i].eeFq,
                                          self[i].editEdNoiseSmp)
            }
        }
        set {
            switch type {
            case .fqSmp:
                self[i].fq = newValue.x
                self[i].smp = newValue.y
            case .fqNoiseSmp:
                self[i].fq = newValue.x
                self[i].noiseSmp = newValue.y
            case .editFqNoiseSmp:
                self[i].fq = newValue.x
                self[i].editNoiseSmp = newValue.y
            case .dFqZero:
                self[i].dFq = newValue.x
            case .ssFqSmp:
                self[i].ssFq = newValue.x
                self[i - 1].edSmp = newValue.y
            case .ssFqNoiseSmp:
                self[i].ssFq = newValue.x
                self[i - 1].edNoiseSmp = newValue.y
            case .editSsFqNoiseSmp:
                self[i].ssFq = newValue.x
                self[i - 1].editEdNoiseSmp = newValue.y
            case .eeFqSmp:
                self[i].eeFq = newValue.x
                self[i].edSmp = newValue.y
            case .eeFqNoiseSmp:
                self[i].eeFq = newValue.x
                self[i].edNoiseSmp = newValue.y
            case .editEeFqNoiseSmp:
                self[i].eeFq = newValue.x
                self[i].editEdNoiseSmp = newValue.y
            }
        }
    }
}
extension Spectlope {
    func divide(_ os: Self) -> Self {
        .init(formants: (0 ..< Swift.min(count, os.count)).map { j in
                .init(sdFq: Swift.max(0, self[j].sdFq.safeDivide(os[j].sdFq)),
                      sFq: Swift.max(0, self[j].sFq.safeDivide(os[j].sFq)),
                      eFq: Swift.max(0, self[j].eFq.safeDivide(os[j].eFq)),
                      edFq: Swift.max(0, self[j].edFq.safeDivide(os[j].edFq)),
                      smp: self[j].smp.safeDivide(os[j].smp),
                      noiseT: self[j].noiseT.safeDivide(os[j].noiseT),
                      edSmp: self[j].edSmp.safeDivide(os[j].edSmp),
                      edNoiseT: self[j].edNoiseT.safeDivide(os[j].edNoiseT))
        })
    }
    func multiply(_ os: Self) -> Self {
        .init(formants: (0 ..< Swift.min(count, os.count)).map { j in
            .init(sdFq: self[j].sdFq * os[j].sdFq,
                  sFq: self[j].sFq * os[j].sFq,
                  eFq: self[j].eFq * os[j].eFq,
                  edFq: self[j].edFq * os[j].edFq,
                  smp: self[j].smp * os[j].smp,
                  noiseT: self[j].noiseT * os[j].noiseT,
                  edSmp: self[j].edSmp * os[j].edSmp,
                  edNoiseT: self[j].edNoiseT * os[j].edNoiseT)
        })
    }
}
extension Spectlope {
    func with(lyric: String) -> Spectlope {
        let phonemes = Phoneme.phonemes(fromHiragana: lyric)
        if let phoneme = phonemes.last, phoneme.isSyllabicJapanese {
            return with(phoneme: phoneme)
        } else {
            return self
        }
    }
    func with(phoneme: Phoneme) -> Spectlope {
        switch phoneme {
        case .a: return self
        case .i:
            var n = self
            n[0].fq *= 0.25
            n[1].fq *= 0.31
            n[1].sdFq *= 1.5
            n[1].edFq *= 1.5
            n[1].edSmp *= 0.43
            n[2].fq *= 1.63
            n[2].smp *= 0.93
            n[3].fq *= 0.92
            n[4].fq *= 0.98
            n[5].fq *= 0.99
            return n
        case .j:
            var n = with(phoneme: .i)
            n[1].smp *= 0.85
            n[2].fq *= 0.85
            n[3].fq *= 0.94
            return n
        case .ja:
            var n = with(phoneme: .j)
            n[4].fq *= 0.98
            return n
        case .ɯ:
            var n = self
            n[0].fq *= 0.33
            n[1].fq *= 0.34
            n[1].edSmp *= 0.52
            n[2].fq *= 1.13
            n[2].smp *= 0.93
            n[3].fq *= 0.87
            n[4].fq *= 0.94
            n[5].fq *= 0.98
            return n
        case .β:
            var n = with(phoneme: .ɯ)
            n[0].fq *= 0.37
            n[1].fq *= 0.82
            n[1].smp *= 0.85
            n[2].fq *= 0.68
            n[2].smp *= 0.78
            return n
        case .e:
            var n = self
            n[0].fq *= 0.08
            n[1].fq *= 0.61
            n[1].sdFq *= 2.36
            n[1].edFq *= 2.36
            n[1].edSmp *= 0.7
            n[2].fq *= 1.35
            n[2].smp *= 0.93
            n[2].edSmp *= 0.96
            n[3].fq *= 0.97
            n[4].fq *= 1.02
            n[5].fq *= 1.01
            return n
        case .o:
            var n = self
            n[0].fq *= 0.08
            n[1].fq *= 0.62
            n[1].edSmp *= 0.7
            n[2].fq *= 0.76
            n[2].edSmp *= 0.67
            n[3].fq *= 0.92
            n[4].fq *= 0.92
            n[5].fq *= 0.98
            return n
        case .nn:
            var n = self
            n[0].fq *= 0.08
            n[0].smp *= 1.01
            n[0].edSmp *= 1.05
            n[1].fq *= 0.33
            n[1].edSmp *= 0.37
            n[2].fq *= 1.05
            n[2].smp *= 0.43
            n[2].edSmp *= 0.34
            n[3].fq *= 0.98
            n[3].smp *= 0.46
            n[3].edSmp *= 0.06
            n[4].fq *= 0.99
            n[4].smp *= 0.3
            n[4].edSmp *= 0.19
            n[5].smp *= 0.14
            n[5].edSmp *= 0.19
            n[6].smp *= 0.25
            n[6].edSmp *= 0.19
            n[7].smp *= 0.25
            n[7].edSmp *= 0.27
            return n
        case .n:
            var n = self
            n[0].fq *= 0
            n[0].edSmp *= 1.05
            n[1].fq *= 0.22
            n[1].edSmp *= 0.37
            n[2].fq *= 1.2
            n[2].smp *= 0.43
            n[2].edSmp *= 0.46
            n[3].fq *= 0.97
            n[3].smp *= 0.6
            n[3].edSmp *= 0.4
            n[4].fq *= 0.99
            n[4].smp *= 0.56
            n[4].edSmp *= 0.4
            n[5].smp *= 0.34
            n[5].edSmp = 0
            n[6].smp = 0
            n[6].edSmp = 0
            n[7].smp = 0
            n[7].edSmp = 0
            return n
        case .nj:
            var n = with(phoneme: .n)
            n[2].fq *= 1.09
            return n
        case .m, .mj:
            var n = with(phoneme: .n)
            n[1].fq *= 0.55
            n[2].fq *= 0.75
            n[3].fq *= 0.86
            n[4].fq *= 0.93
            return n
        case .r:
            var n = self
            n[0].fq *= 0.55
            n[0].edSmp *= 1.05
            n[1].fq *= 0.38
            n[1].smp *= 0.56
            n[1].edSmp *= 0.25
            n[2].fq *= 1.06
            n[2].smp *= 0.3
            n[2].edSmp *= 0.34
            n[3].fq *= 0.9
            n[3].smp *= 0.6
            n[3].edSmp *= 0.28
            n[4].fq *= 0.92
            n[4].smp *= 0.56
            n[4].edSmp *= 0.4
            n[5].smp *= 0.34
            n[5].edSmp = 0
            n[6].smp = 0
            n[6].edSmp = 0
            n[7].smp = 0
            n[7].edSmp = 0
            return n
        case .rj:
            var n = with(phoneme: .r)
            n[2].fq *= 1.32
            return n
        default: return self
        }
    }
}
extension Spectlope: RandomAccessCollection {
    var startIndex: Int { formants.startIndex }
    var endIndex: Int { formants.endIndex }
    subscript(i: Int) -> Formant {
        get { i < formants.count ? formants[i] : .init() }
        set {
            if i < formants.count {
                formants[i] = newValue
            }
        }
    }
}
extension Spectlope: Interpolatable {
    static func linear(_ f0: Self, _ f1: Self, t: Double) -> Self {
        .init(formants: .linear(f0.formants, f1.formants, t: t))
    }
    static func firstSpline(_ f1: Self, _ f2: Self,
                            _ f3: Self, t: Double) -> Self {
        .init(formants: .firstSpline(f1.formants, f2.formants,
                                     f3.formants, t: t))
    }
    static func spline(_ f0: Self, _ f1: Self,
                       _ f2: Self, _ f3: Self, t: Double) -> Self {
        .init(formants: .spline(f0.formants, f1.formants,
                                f2.formants, f3.formants, t: t))
    }
    static func lastSpline(_ f0: Self, _ f1: Self,
                           _ f2: Self, t: Double) -> Self {
        .init(formants: .lastSpline(f0.formants, f1.formants,
                                    f2.formants, t: t))
    }
}
extension Spectlope: MonoInterpolatable {
    static func firstMonospline(_ f1: Self, _ f2: Self,
                                _ f3: Self, with ms: Monospline) -> Self {
        .init(formants: .firstMonospline(f1.formants, f2.formants,
                                         f3.formants, with: ms))
    }
    static func monospline(_ f0: Self, _ f1: Self,
                           _ f2: Self, _ f3: Self,
                           with ms: Monospline) -> Self {
        .init(formants: .monospline(f0.formants, f1.formants,
                                    f2.formants, f3.formants, with: ms))
    }
    static func lastMonospline(_ f0: Self, _ f1: Self,
                               _ f2: Self, with ms: Monospline) ->Self {
        .init(formants: .lastMonospline(f0.formants, f1.formants,
                                        f2.formants, with: ms))
    }
}
extension Spectlope {
    var isFullNoise: Bool {
        !(formants.contains(where: { !$0.isFullNoise }))
    }
    
    func multiplyFq(_ scale: Double) -> Self {
        .init(formants: formants.map { $0.multiplyFq(scale) })
    }
    var maxSinFq: Double {
        self[5].eeFq
    }
    func voiceless(fqScale: Double = 0.8) -> Spectlope {
        var n = self
        n[0].fq *= fqScale
        n[1].fq *= fqScale
        n[4].smp = n[3].edSmp
        return n
    }
    func movedF2(sFq: Double, eFq: Double) -> Spectlope {
        var n = self
        n[2].sFq = sFq
        n[2].eFq = eFq
        return n
    }
    func offVoice() -> Spectlope {
        var sl = off(from: 2)
        sl[0].fq = 0
        sl[0].edSmp = 0
        sl[1].fq = 0
        sl[1].edSmp = 0
        return sl
    }
    func multiplyF2To(f2Smp: Double = 0.85,
                      smp: Double = 0.43) -> Spectlope {
        var v = self
        v[1].edSmp *= f2Smp
        v[2].smp *= f2Smp
        v[2].edSmp *= f2Smp
        if smp != 1 {
            for i in 3 ..< 8 {
                v[i].formMultiplySmp(smp)
            }
        }
        return v
    }
    func off(to i: Int) -> Spectlope {
        var v = self
        for i in 0 ... i {
            v[i].smp = 0
            v[i].edSmp = 0
        }
        return v
    }
    func off(from i: Int) -> Spectlope {
        var v = self
        for i in i ..< 8 {
            v[i].smp = 0
            v[i].edSmp = 0
        }
        return v
    }
    func offNoise() -> Self {
        var sl = self
        for i in 0 ..< sl.count {
            sl[i].noiseT = 0
            sl[i].edNoiseT = 0
        }
        return sl
    }
    func filledNoiseT(from sl: Spectlope) -> Spectlope {
        .init(formants: formants.enumerated().map { $0.element.filledNoiseT(sl[$0.offset]) })
    }
    func filledSmp(from sl: Spectlope) -> Spectlope {
        .init(formants: formants.enumerated().map { $0.element.filledSmp(sl[$0.offset]) })
    }
    func union(smp: Double = 0.85) -> Spectlope {
        var v = self
        v[2].smp *= smp
        return v
    }
    func fricative(isO: Bool) -> Spectlope {
        var sl = off(from: 6)
        sl[0].smp = 0
        sl[0].edSmp *= 0.56
        sl[1].smp *= 0.7
        sl[1].edSmp *= 0.56
        sl[2].smp = 1
        sl[2].edSmp *= 0.56
        sl[3].smp = 1
        sl[3].edSmp *= 0.56
        sl[4].smp = 1
        sl[4].edSmp = 0
        sl[5].fqRange = 5600 ... 6000
        sl[5].smp = isO ? 0.56 : 1
        sl[5].edSmp = 0
        return sl
    }
    func breath() -> Spectlope {
        var sl = off(from: 5)
        sl[0].smp = sl[2].smp * 0.7
        sl[0].edSmp = sl[1].edSmp * 0.7
        sl[1].smp = sl[2].smp * 0.7
        sl[3].smp *= 0.85
        sl[3].edSmp *= 0.7
        sl[4].smp *= 0.7
        return sl
    }
    func toDakuon() -> Spectlope {
        var sl = off(from: 2)
        sl[0].fqRange = 0 ... 400
        sl[0].edSmp *= 0.94
        sl[1].fqRange = 450 ... 500
        sl[1].smp *= 0.85
        sl[1].edSmp = 0
        return sl
    }
    func toNoise() -> Spectlope {
        var sl = self
        sl.formants = sl.formants.map { $0.toNoise() }
        return sl
    }
//    func strong(t: Double) -> Spectlope {
//
//    }
    
    mutating func optimize() {
        var preFq = 0.0
        formants = formants.map {
            var n = $0
            if preFq > $0.sFq {
                n.sFq = preFq
            }
            if n.sFq > n.eFq {
                n.eFq = n.sFq
            }
            preFq = n.eFq
            return n
        }
    }
    func optimized() -> Self {
        var n = self
        n.optimize()
        return n
    }
}

struct Onset: Hashable, Codable {
    var duration = 0.0
    var volume = Volume(smp: 0.7)
    var sec = 0.0
    var attackSec = 0.01
    var releaseSec = 0.02
    var sourceFilter: SourceFilter
}
extension Onset {
    var volumeAmp: Double {
        volume.amp
    }
}

struct KeySpectlope: Hashable, Codable {
    var spectlope: Spectlope
    var sec = 0.0
    
    init(_ spectlope: Spectlope, sec: Double = 0) {
        self.spectlope = spectlope
        self.sec = sec
    }
}

struct Mora: Hashable, Codable {
    var lyric: String
    var fq: Double
    var onsets: [Onset]
    var syllabics: [Phoneme]
    var sourceFilter: SourceFilter
    var deltaSyllabicStartSec = 0.0
    var deltaSinStartSec = 0.0
    var onsetSecDur: Double
    var isVowel = false
    var isDakuon = false
    var isOffVoice = false
    var firstMainSpectlope: Spectlope
    var firstKeySpectlopes: [KeySpectlope]
    var lastKeySpectlopes: [KeySpectlope]
    
    init?(hiragana: String, fq: Double,
          previousMora: Mora?, nextMora: Mora?,
          isVowelReduction: Bool,
          from baseSpectlope: Spectlope) {
        var phonemes = Phoneme.phonemes(fromHiragana: hiragana)
        guard !phonemes.isEmpty else { return nil }
        lyric = hiragana
        self.fq = fq
        
        func spectlope(from phoneme: Phoneme) -> Spectlope? {
            baseSpectlope.with(phoneme: phoneme).optimized()
        }
        
        syllabics = []
        onsetSecDur = 0
        isVowel = false
        switch phonemes.last {
        case .a, .i, .ɯ, .e, .o, .nn:
            syllabics.append(phonemes.last!)
            phonemes.removeLast()
            
            isVowel = phonemes.isEmpty
            deltaSyllabicStartSec = -0.015
        case .sokuon:
            syllabics.append(phonemes.last!)
            
            let ɯSl = baseSpectlope.with(phoneme: .ɯ)
            
            sourceFilter = SourceFilter()
            onsets = []
            firstKeySpectlopes = [.init(ɯSl, sec: 0)]
            firstMainSpectlope = firstKeySpectlopes.first!.spectlope
            lastKeySpectlopes = [.init(ɯSl, sec: 0.1)]
            return
        case .breath:
            syllabics.append(phonemes.last!)
            
            sourceFilter = SourceFilter()
            onsets = []
            
            let aSl = baseSpectlope.with(phoneme: .a)
            
            let tl = 0.05
            
            let npsl = aSl.fricative(isO: syllabics.first == .o).toNoise()
            onsets.append(.init(duration: tl,
                                volume: .init(smp: 0.3),
                                sec: tl,
                                attackSec: 0.02,
                                sourceFilter: .init(npsl)))
            
            let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                Point(1000, 0),
                                                Point(2000, 0.56),
                                                Point(8000, 1),
                                                Point(9000, 1),
                                                Point(15000, 0.56),
                                                Point(17000, 0)])
            onsets.append(.init(duration: tl,
                                volume: .init(smp: 0.125),
                                sec: tl,
                                attackSec: 0.02,
                                releaseSec: 0.03,
                                sourceFilter: sf))
            
            let sl = aSl.breath()
            onsets.append(.init(duration: tl,
                                volume: .init(smp: 0.2),
                                sec: tl,
                                attackSec: 0.02,
                                releaseSec: 0.03,
                                sourceFilter: .init(sl)))
            onsetSecDur = tl
            
            firstKeySpectlopes = [.init(.empty, sec: 0)]
            firstMainSpectlope = firstKeySpectlopes.first!.spectlope
            lastKeySpectlopes = [.init(.empty, sec: 0.1)]
            return
        default: return nil
        }
        let syllabicSpectlope = spectlope(from: syllabics.last!)!
        sourceFilter = .init(syllabicSpectlope)
        
        onsets = []
        
        var isOffVoice = false
        
        enum FirstType {
            case dakuon, haretsu, none
        }
        let firstType: FirstType
        if phonemes.first?.isVoicelessSound ?? false {
            firstType = .haretsu
        } else if phonemes.first?.isVoiceBar ?? false {
            firstType = .dakuon
        } else {
            firstType = .none
        }
        
        enum Youon {
            case j, β, none
        }
        let youon: Youon, youonKsls: [KeySpectlope]
        switch phonemes.last {
        case .j, .ja:
            youon = .j
            let phoneme = phonemes.last!
            phonemes.removeLast()
            
            var sl = spectlope(from: phoneme)!
                .multiplyF2To(f2Smp: 0.7, smp: 1)
            sl[2].sdFq *= 4
            sl[2].edFq *= 4
            youonKsls = [.init(sl, sec: 0.02),
                         .init(sl, sec: 0.1)]
            deltaSyllabicStartSec = -0.035
            syllabics.insert(phoneme, at: 0)
        case .β:
            youon = .β
            phonemes.removeLast()
            
            let sl = spectlope(from: .β)!.multiplyF2To()
            youonKsls = [.init(sl, sec: 0.01),
                         .init(sl, sec: 0.075)]
            deltaSyllabicStartSec = -0.025
            syllabics.insert(.β, at: 0)
        default:
            youon = .none
            
            youonKsls = []
        }
        
        firstKeySpectlopes = []
        lastKeySpectlopes = []
        
        if phonemes.count != 1 {
            onsets = []
        } else {
            let oph = phonemes[0]
            switch oph {
            case .n, .nj:
                let nTl = 0.0325
                let nsl = spectlope(from: oph)!
                let nextSl = youonKsls.first?.spectlope ?? syllabicSpectlope
                var nnsl = nsl
                nnsl[2].edSmp = .linear(nnsl[2].edSmp, nextSl[2].smp, t: 0.075)
                nnsl[3].edSmp = .linear(nnsl[3].edSmp, nextSl[3].smp, t: 0.025)
                firstKeySpectlopes.append(.init(nsl, sec: nTl))
                firstKeySpectlopes.append(.init(nnsl, sec: youon != .none ? 0.01 : 0.015))
                deltaSyllabicStartSec = -0.01
                onsetSecDur = nTl
                deltaSinStartSec -= nTl
            case .m, .mj:
                let mTl = 0.0325
                let msl = spectlope(from: oph)!
                let nextSl = youonKsls.first?.spectlope ?? syllabicSpectlope
                var nmsl = msl
                nmsl[2].edSmp = .linear(nmsl[2].edSmp, nextSl[2].smp, t: 0.075)
                nmsl[3].edSmp = .linear(nmsl[3].edSmp, nextSl[3].smp, t: 0.025)
                firstKeySpectlopes.append(.init(msl, sec: mTl))
                firstKeySpectlopes.append(.init(nmsl, sec: youon != .none ? 0.01 : 0.015))
                deltaSyllabicStartSec = -0.01
                onsetSecDur = mTl
                deltaSinStartSec -= mTl
            case .r, .rj:
                let rTl = 0.01
                let rsl = spectlope(from: oph)!
                let nextSl = youonKsls.first?.spectlope ?? syllabicSpectlope
                var nrsl = rsl
                nrsl[2].edSmp = .linear(nrsl[2].edSmp, nextSl[2].smp, t: 0.075)
                nrsl[3].edSmp = .linear(nrsl[3].edSmp, nextSl[3].smp, t: 0.025)
                firstKeySpectlopes.append(.init(rsl, sec: rTl))
                firstKeySpectlopes.append(.init(nrsl, sec: youon != .none ? 0.01 : 0.05))
                deltaSyllabicStartSec = 0.0
                onsetSecDur = rTl
                deltaSinStartSec -= rTl
                
            case .k, .kj, .g, .gj:
                let kTl = 0.055, kjTl = 0.07, kOTl = 0.015, kjOTl = 0.02
                let gTl = 0.045, gjTl = 0.045, gOTl = 0.015, gjOTl = 0.02
                let isK = oph == .k || oph == .kj
                let isJ = oph == .kj || oph == .gj
                
                let sf: SourceFilter, volume: Volume
                if isJ || syllabics.first == .e {
                    sf = SourceFilter(fqSmps: [Point(0, 0.56),
                                               Point(2800, 0.61),
                                               Point(3000, 1),
                                               Point(3400, 1),
                                               Point(3600, 0.56),
                                               Point(4800, 0.4),
                                               Point(5000, 0)])
                    volume = .init(smp: 0.46)
                } else {
                    switch syllabics.first {
                    case .o:
                        sf = SourceFilter(fqSmps: [Point(0, 0.56),
                                                   Point(800, 0.61),
                                                   Point(1000, 1),
                                                   Point(1600, 1),
                                                   Point(1800, 0.56),
                                                   Point(5800, 0.4),
                                                   Point(6000, 0)])
                    default:
                        sf = SourceFilter(fqSmps: [Point(0, 0.56),
                                                   Point(1400, 0.61),
                                                   Point(1600, 1),
                                                   Point(2500, 1),
                                                   Point(2700, 0.56),
                                                   Point(4800, 0.4),
                                                   Point(5000, 0)])
                    }
                    volume = .init(smp: 0.56)
                }
                
                onsets.append(.init(duration: isK ? (isJ ? kjOTl : kOTl) : (isJ ? gjOTl : gOTl),
                                    volume: volume,
                                    sec: isK ? -0.005 : -0.01,
                                    attackSec: 0.02,
                                    sourceFilter: sf))
                deltaSyllabicStartSec = 0.01
                onsetSecDur = isK ? (isJ ? kjTl : kTl) : (isJ ? gjTl : gTl)
                isOffVoice = true
            case .t, .d:
                let tTl = 0.05, tOTl = 0.01
                let dTl = 0.04, dOTl = 0.01
                let isT = oph == .t
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(4300, 0),
                                                    Point(4500, 1),
                                                    Point(4900, 1),
                                                    Point(5100, 0.7),
                                                    Point(5800, 0.52),
                                                    Point(6000, 0)])
                onsets.append(.init(duration: isT ? tOTl : dOTl,
                                    volume: .init(smp: 0.5),
                                    sec: isT ? 0 : 0.0075,
                                    releaseSec: 0.01,
                                    sourceFilter: sf))
                deltaSyllabicStartSec = 0.01
                onsetSecDur = isT ? tTl : dTl
                isOffVoice = true
            case .p, .pj, .b, .bj:
                let pTl = 0.05, pOTl = 0.01
                let bTl = 0.04, bOTl = 0.01
                let isP = oph == .p || oph == .pj
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(600, 0),
                                                    Point(700, 0.85),
                                                    Point(1100, 0.9),
                                                    Point(1200, 1),
                                                    Point(1600, 1),
                                                    Point(1700, 0.85),
                                                    Point(2800, 0.75),
                                                    Point(3000, 0)])
                onsets.append(.init(duration: isP ? pOTl : bOTl,
                                    volume: .init(smp: 0.4),
                                    sec: isP ? 0.005 : 0.0075,
                                    releaseSec: 0.01,
                                    sourceFilter: sf))
                deltaSyllabicStartSec = 0.02
                onsetSecDur = isP ? pTl : bTl
                isOffVoice = true
                
            case .s, .ts, .dz:
                let sokuonScale: Double
                    = previousMora?.syllabics == [.sokuon]
                    || isVowelReduction ? 1.5 : 1
                let otl, tl: Double, volume: Volume
                switch oph {
                case .s:
                    otl = 0.08 * sokuonScale
                    tl = otl
                    volume = .init(smp: 0.7)
                case .ts:
                    otl = 0.05 * sokuonScale
                    tl = 0.09
                    volume = .init(smp: 0.675)
                case .dz:
                    otl = 0.06 * sokuonScale
                    tl = otl - 0.02 + 0.01
                    volume = .init(smp: 0.65)
                default: fatalError()
                }
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(2600, 0),
                                                    Point(2800, 0.3),
                                                    Point(5800, 0.46),
                                                    Point(6000, 0.75),
                                                    Point(8400, 0.8),
                                                    Point(9000, 1),
                                                    Point(11500, 1),
                                                    Point(14000, 0.8),
                                                    Point(16000, 0.6),
                                                    Point(18000, 0)])
                onsets.append(.init(duration: otl,
                                    volume: volume,
                                    sec: (oph != .dz ? 0.01 : 0.01) + (isVowelReduction ? otl / 3 : 0),
                                    attackSec: oph != .dz ? 0.02 : 0.04,
                                    releaseSec: oph != .dz ? 0.02 : 0.02,
                                    sourceFilter: sf))
                let olt = onsets.last!.attackSec + onsets.last!.releaseSec
                if oph == .ts {
                    let ootl = 0.01
                    let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                        Point(4300, 0),
                                                        Point(4500, 1),
                                                        Point(4900, 1),
                                                        Point(5100, 0.7),
                                                        Point(5800, 0.52),
                                                        Point(6000, 0)])
                    onsets.append(.init(duration: ootl,
                                        volume: .init(smp: 0.3),
                                        sec: -otl - ootl,
                                        releaseSec: 0.01,
                                        sourceFilter: sf))
                }
                deltaSyllabicStartSec = (oph == .ts ? 0.01 : 0) - 0.01
                onsetSecDur = tl - olt
                isOffVoice = true
            case .ɕ, .tɕ, .dʒ:
                let sokuonScale: Double
                    = previousMora?.syllabics == [.sokuon]
                    || isVowelReduction ? 1.5 : 1
                let otl, tl: Double, volume: Volume
                switch oph {
                case .ɕ:
                    otl = 0.085 * sokuonScale
                    tl = otl
                    volume = .init(smp: 0.75)
                case .tɕ:
                    otl = 0.04 * sokuonScale
                    tl = 0.08
                    volume = .init(smp: 0.65)
                case .dʒ:
                    otl = 0.055 * sokuonScale
                    tl = otl - 0.02 + 0.02
                    volume = .init(smp: 0.62)
                default: fatalError()
                }
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(900, 0),
                                                    Point(1000, 0.1),
                                                    Point(3800, 0.2),
                                                    Point(4000, 0.6),
                                                    Point(5200, 0.7),
                                                    Point(6000, 1),
                                                    Point(10500, 1),
                                                    Point(13000, 0.8),
                                                    Point(16000, 0.6),
                                                    Point(18000, 0)])
                onsets.append(.init(duration: otl,
                                    volume: volume,
                                    sec: (oph != .dʒ ? 0.01 : 0.02) + (isVowelReduction ? otl / 3 : 0),
                                    attackSec: oph == .tɕ ? 0.01 : (oph != .dz ? 0.02 : 0.04),
                                    releaseSec: oph != .dz ? 0.02 : 0.01,
                                    sourceFilter: sf))
                let olt = onsets.last!.attackSec + onsets.last!.releaseSec
                if oph == .tɕ {
                    let ootl = 0.01
                    let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                        Point(4300, 0),
                                                        Point(4500, 1),
                                                        Point(4900, 1),
                                                        Point(5100, 0.7),
                                                        Point(5800, 0.52),
                                                        Point(6000, 0)])
                    onsets.append(.init(duration: ootl,
                                        volume: .init(smp: 0.3),
                                        sec: -otl - ootl,
                                        releaseSec: 0.01,
                                        sourceFilter: sf))
                }
                deltaSyllabicStartSec = -0.01
                onsetSecDur = tl - olt
                isOffVoice = true
            case .h:
                let sokuonScale: Double
                    = previousMora?.syllabics == [.sokuon]
                    || isVowelReduction ? 1.5 : 1
                let hTl = 0.06 * sokuonScale
                let psl = youonKsls.first?.spectlope ?? syllabicSpectlope
                let npsl = psl.fricative(isO: syllabics.first == .o).toNoise()
                onsets.append(.init(duration: hTl,
                                    volume: .init(smp: 0.37),
                                    sec: 0.02 + (isVowelReduction ? hTl / 3 : 0),
                                    attackSec: 0.02,
                                    sourceFilter: .init(npsl)))
                deltaSyllabicStartSec = -0.01
                onsetSecDur = hTl - onsets.last!.attackSec - onsets.last!.releaseSec
                isOffVoice = true
            case .ç:
                let sokuonScale: Double
                    = previousMora?.syllabics == [.sokuon]
                    || isVowelReduction ? 1.5 : 1
                let çTl = 0.06 * sokuonScale
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(3100, 0),
                                                    Point(3300, 1),
                                                    Point(4100, 1),
                                                    Point(4300, 0.56),
                                                    Point(4800, 0.7),
                                                    Point(5000, 1),
                                                    Point(10000, 1),
                                                    Point(11000, 0.56),
                                                    Point(12000, 0.3),
                                                    Point(13000, 0)])
                onsets.append(.init(duration: çTl,
                                    volume: .init(smp: 0.37),
                                    sec: 0.02 + (isVowelReduction ? çTl / 3 : 0),
                                    attackSec: 0.02,
                                    sourceFilter: sf))
                deltaSyllabicStartSec = -0.01
                onsetSecDur = çTl - onsets.last!.attackSec - onsets.last!.releaseSec
                isOffVoice = true
            case .ɸ:
                let sokuonScale: Double
                    = previousMora?.syllabics == [.sokuon]
                    || isVowelReduction ? 1.5 : 1
                let ɸTl = 0.06 * sokuonScale
                let sf = SourceFilter(noiseFqSmps: [Point(0, 0),
                                                    Point(1800, 0),
                                                    Point(2000, 0.52),
                                                    Point(5200, 0.7),
                                                    Point(5400, 1),
                                                    Point(5900, 1),
                                                    Point(6100, 0.7),
                                                    Point(9000, 0.66),
                                                    Point(10000, 0.56),
                                                    Point(17000, 0.3),
                                                    Point(18000, 0)])
                onsets.append(.init(duration: ɸTl,
                                    volume: .init(smp: 0.2),
                                    sec: 0.02 + (isVowelReduction ? ɸTl / 3 : 0),
                                    attackSec: 0.02,
                                    sourceFilter: sf))
                deltaSyllabicStartSec = -0.01
                onsetSecDur = ɸTl - onsets.last!.attackSec - onsets.last!.releaseSec
                isOffVoice = true
                
            default: onsets = []
            }
        }
        
        isDakuon = firstType == .dakuon
        
        if isOffVoice && !isDakuon && (syllabics == [.i] || syllabics == [.ɯ]) {
            if previousMora != nil && nextMora == nil {
                if !onsets.isEmpty {
                    let d = onsets[.last].duration * 0.25
                    deltaSyllabicStartSec += d / 2
                    onsetSecDur += d
                    onsets[.last].duration += d
                }
            } else if nextMora != nil
                        && nextMora!.isOffVoice && !nextMora!.isDakuon {
                if !onsets.isEmpty {
                    let d = onsets[.last].duration * 0.25
                    deltaSyllabicStartSec += d / 2
                    onsetSecDur += d
                    onsets[.last].duration += d
                }
            }
        }
        
        firstKeySpectlopes += youonKsls
        firstKeySpectlopes.append(.init(syllabicSpectlope, sec: 0))
        
        firstMainSpectlope = firstKeySpectlopes.first!.spectlope
        
        if isOffVoice && youon == .none {
            let sl = firstMainSpectlope
            if phonemes.last == .g || phonemes.last == .d || phonemes.last == .b {
                let osl: Spectlope
                switch phonemes.last {
                case .g:
                    osl = syllabics.last! == .o || syllabics.last! == .ɯ ?
                        sl.movedF2(sFq: 1200, eFq: 1400) :
                        sl.movedF2(sFq: 2800, eFq: 3200)
                case .d: osl = sl.movedF2(sFq: 1600, eFq: 2000)
                case .b: osl = sl.movedF2(sFq: 600, eFq: 800)
                default: fatalError()
                }
                let nsl = Spectlope.linear(osl, sl, t: 0.8).voiceless()
                firstKeySpectlopes.insert(.init(nsl, sec: 0.075 * 0.25), at: 0)
                let nnsl = Spectlope.linear(nsl, firstMainSpectlope, t: 0.25)
                    .filledSmp(from: firstMainSpectlope)
                firstKeySpectlopes.insert(.init(nnsl, sec: 0.075 * 0.75), at: 1)
            } else if let preSl = previousMora?.mainSpectlope {
                let nsl = Spectlope.linear(preSl.offVoice(), sl, t: 0.65)
                    .voiceless()
                firstKeySpectlopes.insert(.init(nsl, sec: 0.075 * 0.25), at: 0)
                let nnsl = Spectlope.linear(nsl, firstMainSpectlope, t: 0.25)
                    .filledSmp(from: firstMainSpectlope)
                firstKeySpectlopes.insert(.init(nnsl, sec: 0.075 * 0.75), at: 1)
            }
        } else if isVowel {
            let nsl = firstMainSpectlope.offVoice()
            firstKeySpectlopes.insert(.init(nsl, sec: 0.02), at: 0)
        }
        
        if firstType == .dakuon {
            let dakuTl = onsetSecDur * 0.9
            let sf = SourceFilter(fqSmps: [Point(0, 1),
                                           Point(400, 1),
                                           Point(700, 0.56),
                                           Point(2500, 0.43),
                                           Point(3500, 0)])
            onsets.append(.init(duration: dakuTl, volume: .init(smp: 0.5),
                                sourceFilter: sf))
            
            let sl = firstKeySpectlopes[.first].spectlope.toDakuon()
            firstKeySpectlopes.insert(.init(sl, sec: 0.0075), at: 0)
            firstKeySpectlopes.insert(.init(sl, sec: 0.01), at: 1)
            deltaSinStartSec = -0.0075
        }
        
        var t = 0.0
        firstKeySpectlopes = firstKeySpectlopes.map {
            let ks = KeySpectlope($0.spectlope, sec: t)
            t += $0.sec
            return ks
        }
        
        let preSl = firstKeySpectlopes.last!.spectlope.multiplyFq(1.02)
        lastKeySpectlopes.append(.init(preSl, sec: 0))
        if let nextMora {
            let sl = nextMora.firstMainSpectlope
            if nextMora.isOffVoice {
                let nsl = Spectlope.linear(preSl, sl, t: 0.3).offVoice()
                let nnsl = Spectlope.linear(preSl, nsl, t: 0.25)
                lastKeySpectlopes.append(.init(nnsl, sec: 0.05 * 0.25))
                lastKeySpectlopes.append(.init(nsl, sec: 0.05))
            } else {
                let nsl = Spectlope.linear(preSl, sl, t: 0.35).union()
                let nnsl = Spectlope.linear(preSl, nsl, t: 0.25)
                lastKeySpectlopes.append(.init(nnsl, sec: 0.1125 * 0.25))
                lastKeySpectlopes.append(.init(nsl, sec: 0.1125))
            }
        } else {
            let nsl = preSl.offVoice()
            let nnsl = Spectlope.linear(preSl, nsl, t: 0.25)
            lastKeySpectlopes.append(.init(nnsl, sec: 0.075 * 0.25))
            lastKeySpectlopes.append(.init(nsl, sec: 0.075))
        }
        
        self.isOffVoice = isOffVoice
    }
}
extension Mora {
    func spectlopeInterpolation(fromDuration dur: Double) -> Interpolation<Spectlope> {
        let fks = firstKeySpectlopes.map {
            Interpolation.Key(value: $0.spectlope,
                              time: $0.sec, type: .spline)
        }
        let lks = lastKeySpectlopes.map {
            Interpolation.Key(value: $0.spectlope,
                              time: dur - lastKeySpectlopes.last!.sec + $0.sec, type: .spline)
        }
        return .init(keys: fks + lks, duration: dur)
    }
    var mainSpectlope: Spectlope {
        firstKeySpectlopes.last!.spectlope
    }
    func spectlopes(atSec sec: Double, lastSec: Double) -> Spectlope {
        if sec < firstKeySpectlopes.first!.sec {
            return firstKeySpectlopes.first!.spectlope
        } else if sec >= lastSec {
            return lastKeySpectlopes.last!.spectlope
        } else {
            return spectlopeInterpolation(fromDuration: lastSec)
                .value(withTime: sec) ?? lastKeySpectlopes.last!.spectlope
        }
    }
}

enum Phoneme: String, Hashable, Codable, CaseIterable {
    case a, i, ɯ, e, o, j, ja, β, nn,
         k, kj, s, ɕ, t, tɕ, ts, n, nj, h, ç, ɸ, p, pj, m, mj, r, rj,
         g, gj, dz, dʒ, d, b, bj,
         sokuon, breath
}
extension Phoneme {
    var isVowel: Bool {
        switch self {
        case .a, .i, .ɯ, .e, .o: true
        default: false
        }
    }
    var isSyllabicJapanese: Bool {
        switch self {
        case .a, .i, .ɯ, .e, .o, .nn: true
        default: false
        }
    }
    var isConsonant: Bool {
        !isVowel
    }
    var isVoiceBar: Bool {
        switch self {
        case .g, .gj, .dz, .dʒ, .d, .b, .bj: true
        default: false
        }
    }
    var isVoicelessSound: Bool {
        switch self {
        case .k, .kj, .s, .ɕ, .t, .tɕ, .ts, .h, .ç, .ɸ, .p, .pj: true
        default: false
        }
    }
}
extension Phoneme {
    static func phonemes(fromHiragana hiragana: String) -> [Phoneme] {
        switch hiragana {
        case "あ": [.a]
        case "い": [.i]
        case "う": [.ɯ]
        case "え": [.e]
        case "お", "を": [.o]
        case "か": [.k, .a]
        case "き": [.kj, .i]
        case "く": [.k, .ɯ]
        case "け": [.k, .e]
        case "こ": [.k, .o]
        case "きゃ": [.kj, .ja, .a]
        case "きゅ": [.kj, .j, .ɯ]
        case "きぇ": [.kj, .j, .e]
        case "きょ": [.kj, .j, .o]
        case "くぁ", "くゎ": [.k, .β, .a]
        case "くぃ": [.k, .β, .i]
        case "くぇ": [.k, .β, .e]
        case "くぉ": [.k, .β, .o]
        case "が": [.g, .a]
        case "ぎ": [.gj, .i]
        case "ぐ": [.g, .ɯ]
        case "げ": [.g, .e]
        case "ご": [.g, .o]
        case "ぎゃ": [.gj, .ja, .a]
        case "ぎゅ": [.gj, .j, .ɯ]
        case "ぎぇ": [.gj, .j, .e]
        case "ぎょ": [.gj, .j, .o]
        case "ぐぁ", "ぐゎ": [.g, .β, .a]
        case "ぐぃ": [.g, .β, .ɯ]
        case "ぐぇ": [.g, .β, .e]
        case "ぐぉ": [.g, .β, .o]
        case "さ": [.s, .a]
        case "し": [.ɕ, .i]
        case "す": [.s, .ɯ]
        case "せ": [.s, .e]
        case "そ": [.s, .o]
        case "しゃ": [.ɕ, .a]
        case "しゅ": [.ɕ, .ɯ]
        case "しぇ": [.ɕ, .e]
        case "しょ": [.ɕ, .o]
        case "すぁ", "すゎ": [.s, .β, .a]
        case "すぃ": [.s, .β, .i]
        case "すぇ": [.s, .β, .e]
        case "すぉ": [.s, .β, .o]
        case "ざ": [.dz, .a]
        case "じ", "ぢ": [.dʒ, .i]
        case "ず", "づ": [.dz, .ɯ]
        case "ぜ": [.dz, .e]
        case "ぞ": [.dz, .o]
        case "じゃ", "ぢゃ": [.dʒ, .ja, .a]
        case "じゅ", "ぢゅ": [.dʒ, .j, .ɯ]
        case "じぇ", "ぢぇ": [.dʒ, .j, .e]
        case "じょ", "ぢょ": [.dʒ, .j, .o]
        case "ずぁ", "ずゎ", "づぁ", "づゎ": [.dz, .β, .a]
        case "ずぃ", "づぃ": [.dz, .β, .i]
        case "ずぇ", "づぇ": [.dz, .β, .e]
        case "ずぉ", "づぉ": [.dz, .β, .o]
        case "た": [.t, .a]
        case "ち": [.tɕ, .i]
        case "つ": [.ts, .ɯ]
        case "て": [.t, .e]
        case "と": [.t, .o]
        case "てぃ": [.t, .i]
        case "とぅ": [.t, .ɯ]
        case "ちゃ": [.tɕ, .ja, .a]
        case "ちゅ": [.tɕ, .j, .ɯ]
        case "ちぇ": [.tɕ, .j, .e]
        case "ちょ": [.tɕ, .j, .o]
        case "つぁ": [.ts, .β, .a]
        case "つぃ": [.ts, .β, .i]
        case "つぇ": [.ts, .β, .e]
        case "つぉ": [.ts, .β, .o]
        case "だ": [.d, .a]
        case "で": [.d, .e]
        case "ど": [.d, .o]
        case "でぃ": [.d, .i]
        case "どぅ": [.d, .ɯ]
        case "な": [.n, .a]
        case "に": [.nj, .i]
        case "ぬ": [.n, .ɯ]
        case "ね": [.n, .e]
        case "の": [.n, .o]
        case "にゃ": [.nj, .ja, .a]
        case "にゅ": [.nj, .j, .ɯ]
        case "にぇ": [.nj, .j, .e]
        case "にょ": [.nj, .j, .o]
        case "ぬぁ", "ぬゎ": [.n, .β, .a]
        case "ぬぃ": [.n, .β, .i]
        case "ぬぇ": [.n, .β, .e]
        case "ぬぉ": [.n, .β, .o]
        case "は": [.h, .a]
        case "ひ": [.ç, .i]
        case "ふ": [.ɸ, .ɯ]
        case "へ": [.h, .e]
        case "ほ": [.h, .o]
        case "ひゃ": [.ç, .ja, .a]
        case "ひゅ": [.ç, .j, .ɯ]
        case "ひぇ": [.ç, .j, .e]
        case "ひょ": [.ç, .j, .o]
        case "ふぁ": [.ɸ, .β, .a]
        case "ふぃ": [.ɸ, .β, .i]
        case "ふぇ": [.ɸ, .β, .e]
        case "ふぉ": [.ɸ, .β, .o]
        case "ば": [.b, .a]
        case "び": [.bj, .i]
        case "ぶ": [.b, .ɯ]
        case "べ": [.b, .e]
        case "ぼ": [.b, .o]
        case "びゃ": [.bj, .ja, .a]
        case "びゅ": [.bj, .j, .ɯ]
        case "びぇ": [.bj, .j, .e]
        case "びょ": [.bj, .j, .o]
        case "ぶぁ", "ぶゎ": [.b, .β, .a]
        case "ぶぃ": [.b, .β, .i]
        case "ぶぇ": [.b, .β, .e]
        case "ぶぉ": [.b, .β, .o]
        case "ぱ": [.p, .a]
        case "ぴ": [.pj, .i]
        case "ぷ": [.p, .ɯ]
        case "ぺ": [.p, .e]
        case "ぽ": [.p, .o]
        case "ぴゃ": [.pj, .ja, .a]
        case "ぴゅ": [.pj, .j, .ɯ]
        case "ぴぇ": [.pj, .j, .e]
        case "ぴょ": [.pj, .j, .o]
        case "ぷぁ", "ぷゎ": [.p, .β, .a]
        case "ぷぃ": [.p, .β, .i]
        case "ぷぇ": [.p, .β, .e]
        case "ぷぉ": [.p, .β, .o]
        case "ま": [.m, .a]
        case "み": [.mj, .i]
        case "む": [.m, .ɯ]
        case "め": [.m, .e]
        case "も": [.m, .o]
        case "みゃ": [.mj, .ja, .a]
        case "みゅ": [.mj, .j, .ɯ]
        case "みぇ": [.mj, .j, .e]
        case "みょ": [.mj, .j, .o]
        case "むぁ", "むゎ": [.m, .β, .a]
        case "むぃ": [.m, .β, .i]
        case "むぇ": [.m, .β, .e]
        case "むぉ": [.m, .β, .o]
        case "や": [.ja, .a]
        case "ゆ": [.j, .ɯ]
        case "いぇ": [.j, .e]
        case "よ": [.j, .o]
        case "ら": [.r, .a]
        case "り": [.rj, .i]
        case "る": [.r, .ɯ]
        case "れ": [.r, .e]
        case "ろ": [.r, .o]
        case "りゃ": [.rj, .ja, .a]
        case "りゅ": [.rj, .j, .ɯ]
        case "りぇ": [.rj, .j, .e]
        case "りょ": [.rj, .j, .o]
        case "るぁ", "るゎ": [.r, .β, .a]
        case "るぃ": [.r, .β, .i]
        case "るぇ": [.r, .β, .e]
        case "るぉ": [.r, .β, .o]
        case "わ": [.β, .a]
        case "うぃ": [.β, .i]
        case "うぇ": [.β, .e]
        case "うぉ": [.β, .o]
        case "ん": [.nn]
        case "っ": [.sokuon]
        case "^": [.breath]
        default: []
        }
    }
    static func isSyllabicJapanese(_ phonemes: [Phoneme]) -> Bool {
        phonemes.count == 1 && phonemes[0].isSyllabicJapanese
    }
}

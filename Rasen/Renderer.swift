// Copyright 2024 Cii
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

//#if os(macOS) && os(iOS) && os(watchOS) && os(tvOS) && os(visionOS)
import MetalKit
import MetalPerformanceShaders
//#elseif os(linux) && os(windows)
//#endif

final class Renderer {
    let device: any MTLDevice
    let library: any MTLLibrary
    let commandQueue: any MTLCommandQueue
    let colorSpace = ColorSpace.default.cg!
    let pixelFormat = MTLPixelFormat.bgra8Unorm
    let imageColorSpace = ColorSpace.export.cg!
    let imagePixelFormat = MTLPixelFormat.rgba8Unorm
    let hdrColorSpace = CGColorSpace.sRGBHDRColorSpace!
    let hdrPixelFormat = MTLPixelFormat.rgba16Float
    var defaultColorBuffers: [RGBA: Buffer]
    
    nonisolated(unsafe) static let shared = try! Renderer()
    
    static var metalError: any Error {
        NSError(domain: NSCocoaErrorDomain, code: 0)
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Renderer.metalError
        }
        self.device = device
        guard let library = device.makeDefaultLibrary() else {
            throw Renderer.metalError
        }
        self.library = library
        guard let commandQueue = device.makeCommandQueue() else {
            throw Renderer.metalError
        }
        self.commandQueue = commandQueue
        
        var n = [RGBA: Buffer]()
        func append(_ color: Color) {
            let rgba = color.with(ColorSpace.default).rgba.premultipliedAlpha
            n[rgba] = device.makeBuffer(rgba)
        }
        append(.background)
        append(.disabled)
        append(.border)
        append(.subBorder)
        append(.draft)
        append(.selected)
        append(.subSelected)
        append(.diselected)
        append(.subDiselected)
        append(.removing)
        append(.subRemoving)
        append(.content)
        append(.interpolated)
        append(.warning)
        defaultColorBuffers = n
    }
    func appendColorBuffer(with color: Color) {
        let rgba = color.with(ColorSpace.default).rgba.premultipliedAlpha
        if defaultColorBuffers[rgba] == nil {
            defaultColorBuffers[rgba] = device.makeBuffer(rgba)
        }
    }
    func colorBuffer(with color: Color) -> Buffer? {
        let rgba = color.with(ColorSpace.default).rgba.premultipliedAlpha
        if let buffer = defaultColorBuffers[rgba] {
            return buffer
        }
        return device.makeBuffer(rgba)
    }
}

final class Renderstate {
    let sampleCount: Int
    let opaqueColorRenderPipelineState: any MTLRenderPipelineState
    let alphaColorRenderPipelineState: any MTLRenderPipelineState
    let colorsRenderPipelineState: any MTLRenderPipelineState
    let maxColorsRenderPipelineState: any MTLRenderPipelineState
    let opaqueTextureRenderPipelineState: any MTLRenderPipelineState
    let alphaTextureRenderPipelineState: any MTLRenderPipelineState
    let stencilRenderPipelineState: any MTLRenderPipelineState
    let stencilBezierRenderPipelineState: any MTLRenderPipelineState
    let invertDepthStencilState: any MTLDepthStencilState
    let normalDepthStencilState: any MTLDepthStencilState
    let clippingDepthStencilState: any MTLDepthStencilState
    let cacheSamplerState: any MTLSamplerState
    
    nonisolated(unsafe) static let sampleCount1 = try? Renderstate(sampleCount: 1)
    nonisolated(unsafe) static let sampleCount4 = try? Renderstate(sampleCount: 4)
    nonisolated(unsafe) static let sampleCount8 = try? Renderstate(sampleCount: 8)
    
    init(sampleCount: Int) throws {
        let device = Renderer.shared.device
        let library = Renderer.shared.library
        let pixelFormat = Renderer.shared.pixelFormat
        
        self.sampleCount = sampleCount
        
        let opaqueColorD = MTLRenderPipelineDescriptor()
        opaqueColorD.vertexFunction = library.makeFunction(name: "basicVertex")
        opaqueColorD.fragmentFunction = library.makeFunction(name: "basicFragment")
        opaqueColorD.colorAttachments[0].pixelFormat = pixelFormat
        opaqueColorD.stencilAttachmentPixelFormat = .stencil8
        opaqueColorD.rasterSampleCount = sampleCount
        opaqueColorRenderPipelineState = try device.makeRenderPipelineState(descriptor: opaqueColorD)
        
        let alphaColorD = MTLRenderPipelineDescriptor()
        alphaColorD.vertexFunction = library.makeFunction(name: "basicVertex")
        alphaColorD.fragmentFunction = library.makeFunction(name: "basicFragment")
        alphaColorD.colorAttachments[0].isBlendingEnabled = true
        alphaColorD.colorAttachments[0].rgbBlendOperation = .add
        alphaColorD.colorAttachments[0].alphaBlendOperation = .add
        alphaColorD.colorAttachments[0].sourceRGBBlendFactor = .one
        alphaColorD.colorAttachments[0].sourceAlphaBlendFactor = .one
        alphaColorD.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        alphaColorD.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        alphaColorD.colorAttachments[0].pixelFormat = pixelFormat
        alphaColorD.stencilAttachmentPixelFormat = .stencil8
        alphaColorD.rasterSampleCount = sampleCount
        alphaColorRenderPipelineState = try device.makeRenderPipelineState(descriptor: alphaColorD)
        
        let alphaColorsD = MTLRenderPipelineDescriptor()
        alphaColorsD.vertexFunction = library.makeFunction(name: "colorsVertex")
        alphaColorsD.fragmentFunction = library.makeFunction(name: "basicFragment")
        alphaColorsD.colorAttachments[0].isBlendingEnabled = true
        alphaColorsD.colorAttachments[0].rgbBlendOperation = .add
        alphaColorsD.colorAttachments[0].alphaBlendOperation = .add
        alphaColorsD.colorAttachments[0].sourceRGBBlendFactor = .one
        alphaColorsD.colorAttachments[0].sourceAlphaBlendFactor = .one
        alphaColorsD.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        alphaColorsD.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        alphaColorsD.colorAttachments[0].pixelFormat = pixelFormat
        alphaColorsD.stencilAttachmentPixelFormat = .stencil8
        alphaColorsD.rasterSampleCount = sampleCount
        colorsRenderPipelineState = try device.makeRenderPipelineState(descriptor: alphaColorsD)
        
        let maxColorsD = MTLRenderPipelineDescriptor()
        maxColorsD.vertexFunction = library.makeFunction(name: "colorsVertex")
        maxColorsD.fragmentFunction = library.makeFunction(name: "basicFragment")
        maxColorsD.colorAttachments[0].isBlendingEnabled = true
        maxColorsD.colorAttachments[0].rgbBlendOperation = .min
        maxColorsD.colorAttachments[0].alphaBlendOperation = .min
        maxColorsD.colorAttachments[0].sourceRGBBlendFactor = .one
        maxColorsD.colorAttachments[0].sourceAlphaBlendFactor = .one
        maxColorsD.colorAttachments[0].destinationRGBBlendFactor = .one
        maxColorsD.colorAttachments[0].destinationAlphaBlendFactor = .one
        maxColorsD.colorAttachments[0].pixelFormat = pixelFormat
        maxColorsD.stencilAttachmentPixelFormat = .stencil8
        maxColorsD.rasterSampleCount = sampleCount
        maxColorsRenderPipelineState = try device.makeRenderPipelineState(descriptor: maxColorsD)
        
        let opaqueTextureD = MTLRenderPipelineDescriptor()
        opaqueTextureD.vertexFunction = library.makeFunction(name: "textureVertex")
        opaqueTextureD.fragmentFunction = library.makeFunction(name: "textureFragment")
        opaqueTextureD.colorAttachments[0].pixelFormat = pixelFormat
        opaqueTextureD.stencilAttachmentPixelFormat = .stencil8
        opaqueTextureD.rasterSampleCount = sampleCount
        opaqueTextureRenderPipelineState = try device.makeRenderPipelineState(descriptor: opaqueTextureD)
        
        let alphaTextureD = MTLRenderPipelineDescriptor()
        alphaTextureD.vertexFunction = library.makeFunction(name: "textureVertex")
        alphaTextureD.fragmentFunction = library.makeFunction(name: "textureFragment")
        alphaTextureD.colorAttachments[0].isBlendingEnabled = true
        alphaTextureD.colorAttachments[0].rgbBlendOperation = .add
        alphaTextureD.colorAttachments[0].alphaBlendOperation = .add
        alphaTextureD.colorAttachments[0].sourceRGBBlendFactor = .one
        alphaTextureD.colorAttachments[0].sourceAlphaBlendFactor = .one
        alphaTextureD.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        alphaTextureD.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        alphaTextureD.colorAttachments[0].pixelFormat = pixelFormat
        alphaTextureD.stencilAttachmentPixelFormat = .stencil8
        alphaTextureD.rasterSampleCount = sampleCount
        alphaTextureRenderPipelineState = try device.makeRenderPipelineState(descriptor: alphaTextureD)
        
        let stencilD = MTLRenderPipelineDescriptor()
        stencilD.isAlphaToCoverageEnabled = true
        stencilD.vertexFunction = library.makeFunction(name: "stencilVertex")
        stencilD.fragmentFunction = nil
        stencilD.colorAttachments[0].pixelFormat = pixelFormat
        stencilD.colorAttachments[0].writeMask = []
        stencilD.stencilAttachmentPixelFormat = .stencil8
        stencilD.rasterSampleCount = sampleCount
        stencilRenderPipelineState = try device.makeRenderPipelineState(descriptor: stencilD)
        
        let stencilBezierD = MTLRenderPipelineDescriptor()
        stencilBezierD.isAlphaToCoverageEnabled = true
        stencilBezierD.vertexFunction = library.makeFunction(name: "stencilBVertex")
        stencilBezierD.fragmentFunction = library.makeFunction(name: "stencilBFragment")
        stencilBezierD.colorAttachments[0].pixelFormat = pixelFormat
        stencilBezierD.colorAttachments[0].writeMask = []
        stencilBezierD.stencilAttachmentPixelFormat = .stencil8
        stencilBezierD.rasterSampleCount = sampleCount
        stencilBezierRenderPipelineState = try device.makeRenderPipelineState(descriptor: stencilBezierD)
        
        let invertStencilD = MTLStencilDescriptor()
        invertStencilD.stencilFailureOperation = .invert
        invertStencilD.depthStencilPassOperation = .invert
        let invertDepthStencilD = MTLDepthStencilDescriptor()
        invertDepthStencilD.backFaceStencil = invertStencilD
        invertDepthStencilD.frontFaceStencil = invertStencilD
        guard let ss = device.makeDepthStencilState(descriptor: invertDepthStencilD) else {
            throw Renderer.metalError
        }
        invertDepthStencilState = ss
        
        let clippingStencilD = MTLStencilDescriptor()
        clippingStencilD.stencilCompareFunction = .notEqual
        clippingStencilD.stencilFailureOperation = .keep
        clippingStencilD.depthStencilPassOperation = .zero
        let clippingDepthStecilD = MTLDepthStencilDescriptor()
        clippingDepthStecilD.backFaceStencil = clippingStencilD
        clippingDepthStecilD.frontFaceStencil = clippingStencilD
        guard let cs = device.makeDepthStencilState(descriptor: clippingDepthStecilD) else {
            throw Renderer.metalError
        }
        clippingDepthStencilState = cs
        
        let normalDepthStencilD = MTLDepthStencilDescriptor()
        guard let ncs = device.makeDepthStencilState(descriptor: normalDepthStencilD) else {
            throw Renderer.metalError
        }
        normalDepthStencilState = ncs
        
        let cacheSamplerD = MTLSamplerDescriptor()
        cacheSamplerD.minFilter = .nearest
        cacheSamplerD.magFilter = .linear
        guard let ncss = device.makeSamplerState(descriptor: cacheSamplerD) else {
            throw Renderer.metalError
        }
        cacheSamplerState = ncss
    }
}

final class DynamicBuffer {
    static let maxInflightBuffers = 3
    private let semaphore = DispatchSemaphore(value: DynamicBuffer.maxInflightBuffers)
    var buffers = [Buffer?]()
    var bufferIndex = 0
    init() {
        buffers = (0 ..< DynamicBuffer.maxInflightBuffers).map { _ in
            Renderer.shared.device.makeBuffer(Transform.identity.floatData4x4)
        }
    }
    func next() -> Buffer? {
        semaphore.wait()
        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % DynamicBuffer.maxInflightBuffers
        return buffer
    }
    func signal() {
        semaphore.signal()
    }
}

final class SubMTKView: MTKView, MTKViewDelegate,
                        NSTextInputClient, NSMenuItemValidation, NSMenuDelegate {
    static let enabledAnimationKey = "enabledAnimation"
    static let isHiddenActionListKey = "isHiddenActionList"
    static let isShownTrackpadAlternativeKey = "isShownTrackpadAlternative"
    private(set) var document: Document
    let renderstate = Renderstate.sampleCount4!
    
    var isShownDebug = false
    var isShownClock = false
    private var updateDebugCount = 0
    private let debugNode = Node(attitude: Attitude(position: Point(5, 5)),
                                 fillType: .color(.content))
    
    private var sheetActionNode, rootActionNode: Node?,
                actionIsEditingSheet = true
    private var actionNode: Node? {
        actionIsEditingSheet ? sheetActionNode : rootActionNode
    }
    var isHiddenActionList = true {
        didSet {
            
            guard isHiddenActionList != oldValue else { return }
            updateActionList()
            if isShownTrackpadAlternative {
                updateTrackpadAlternativePositions()
            }
        }
    }
    private func makeActionNode(isEditingSheet: Bool) -> Node {
        let actionNode = ActionList.default.node(isEditingSheet: isEditingSheet)
        let b = document.screenBounds
        let w = b.maxX - (actionNode.bounds?.maxX ?? 0)
        let h = b.midY - (actionNode.bounds?.midY ?? 0)
        actionNode.attitude.position = Point(w, h)
        return actionNode
    }
    private func updateActionList() {
        if isHiddenActionList {
            sheetActionNode = nil
            rootActionNode = nil
        } else if sheetActionNode == nil || rootActionNode == nil {
            sheetActionNode = makeActionNode(isEditingSheet: true)
            rootActionNode = makeActionNode(isEditingSheet: false)
        }
        actionIsEditingSheet = document.isEditingSheet
        update()
    }
    
    func update() {
        needsDisplay = true
    }
    
    required init(url: URL, frame: NSRect = NSRect()) {
        self.document = Document(url: url)
        
        super.init(frame: frame, device: Renderer.shared.device)
        delegate = self
        sampleCount = renderstate.sampleCount
        depthStencilPixelFormat = .stencil8
        clearColor = document.backgroundColor.mtl
        
        if ColorSpace.default.isHDR {
            colorPixelFormat = Renderer.shared.hdrPixelFormat
            colorspace = Renderer.shared.hdrColorSpace
            (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        } else {
            colorPixelFormat = Renderer.shared.pixelFormat
            colorspace = Renderer.shared.colorSpace
        }
        
        isPaused = true
        enableSetNeedsDisplay = true
        self.allowedTouchTypes = .indirect
        self.wantsRestingTouches = true
        setupDocument()
        
        if !UserDefaults.standard.bool(forKey: SubMTKView.isHiddenActionListKey) {
            isHiddenActionList = false
            updateActionList()
        }
        
        if UserDefaults.standard.bool(forKey: SubMTKView.isShownTrackpadAlternativeKey) {
            isShownTrackpadAlternative = true
            updateTrackpadAlternative()
        }
        
        updateWithAppearance()
    }
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func cancelTasks() {
        scrollTimer?.cancel()
        scrollTimer = nil
        pinchTimer?.cancel()
        pinchTimer = nil
    }
    
    override func viewDidChangeEffectiveAppearance() {
        updateWithAppearance()
    }
    var enabledAppearance = false {
        didSet {
            guard enabledAppearance != oldValue else { return }
            updateWithAppearance()
        }
    }
    func updateWithAppearance() {
        if enabledAppearance {
            Appearance.current
                = NSApp.effectiveAppearance.name == .darkAqua ? .dark : .light
            
            window?.invalidateCursorRects(for: self)
            addCursorRect(bounds, cursor: Cursor.current.ns)
            
            switch Appearance.current {
            case .light:
                if layer?.filters != nil {
                    layer?.filters = nil
                }
            case .dark:
                 layer?.filters = SubMTKView.darkFilters()
                // change edit lightness
                // export
            }
        } else {
            if layer?.filters != nil {
                layer?.filters = nil
            }
        }
    }
    static func darkFilters() -> [CIFilter] {
        if let invertFilter = CIFilter(name: "CIColorInvert"),
           let gammaFilter = CIFilter(name: "CIGammaAdjust"),
           let brightnessFilter = CIFilter(name: "CIColorControls"),
           let hueFilter = CIFilter(name: "CIHueAdjust") {
            
            gammaFilter.setValue(1.75, forKey: "inputPower")
            brightnessFilter.setValue(0.02, forKey: "inputBrightness")
            hueFilter.setValue(Double.pi, forKey: "inputAngle")
            
            return [invertFilter, gammaFilter, brightnessFilter, hueFilter]
        } else {
            return []
        }
    }
    
    func setupDocument() {
        document.backgroundColorNotifications.append { [weak self] (_, backgroundColor) in
            self?.clearColor = backgroundColor.mtl
            self?.update()
        }
        document.cursorNotifications.append { [weak self] (_, cursor) in
            guard let self else { return }
            self.window?.invalidateCursorRects(for: self)
            self.addCursorRect(self.bounds, cursor: cursor.ns)
            Cursor.current = cursor
        }
        document.cameraNotifications.append { [weak self] (_, _) in
            guard let self else { return }
            if !self.isHiddenActionList {
                if self.actionIsEditingSheet != self.document.isEditingSheet {
                    self.updateActionList()
                }
            }
            self.update()
        }
        document.rootNode.allChildrenAndSelf { $0.owner = self }
        
        document.cursorPoint = clippedScreenPointFromCursor.my
    }
    
    var isShownTrackpadAlternative = false {
        didSet {
            guard isShownTrackpadAlternative != oldValue else { return }
            updateTrackpadAlternative()
        }
    }
    private var trackpadView: NSView?,
                lookUpButton: NSButton?,
                scrollButton: NSButton?,
                zoomButton: NSButton?,
                rotateButton: NSButton?
    func updateTrackpadAlternative() {
        if isShownTrackpadAlternative {
            let trackpadView = SubNSTrackpadView(frame: NSRect())
            let lookUpButton = SubNSButton(frame: NSRect(),
                                           .lookUp) { [weak self] (event, dp) in
                guard let self else { return }
                if event.phase == .began,
                   let r = self.document.selections
                    .first(where: { self.document.worldBounds.intersects($0.rect) })?.rect {
                    
                    let p = r.centerPoint
                    let sp = self.document.convertWorldToScreen(p)
                    self.document.inputKey(self.inputKeyEventWith(at: sp, .lookUpTap, .began))
                    self.document.inputKey(self.inputKeyEventWith(at: sp, .lookUpTap, .ended))
                }
            }
            trackpadView.addSubview(lookUpButton)
            self.lookUpButton = lookUpButton
            
            let scrollButton = SubNSButton(frame: NSRect(),
                                           .scroll) { [weak self] (event, dp) in
                guard let self else { return }
                let nEvent = ScrollEvent(screenPoint: self.document.screenBounds.centerPoint,
                                         time: event.time,
                                         scrollDeltaPoint: Point(dp.x, -dp.y) * 2,
                                         phase: event.phase,
                                         touchPhase: nil,
                                         momentumPhase: nil)
                self.document.scroll(nEvent)
            }
            trackpadView.addSubview(scrollButton)
            self.scrollButton = scrollButton
            
            let zoomButton = SubNSButton(frame: NSRect(),
                                         .zoom) { [weak self] (event, dp) in
                guard let self else { return }
                let nEvent = PinchEvent(screenPoint: self.document.screenBounds.centerPoint,
                                        time: event.time,
                                        magnification: -dp.y / 100,
                                        phase: event.phase)
                self.document.pinch(nEvent)
            }
            trackpadView.addSubview(zoomButton)
            self.zoomButton = zoomButton
            
            let rotateButton = SubNSButton(frame: NSRect(),
                                           .rotate) { [weak self] (event, dp) in
                guard let self else { return }
                let nEvent = RotateEvent(screenPoint: self.document.screenBounds.centerPoint,
                                         time: event.time,
                                         rotationQuantity: -dp.x / 10,
                                         phase: event.phase)
                self.document.rotate(nEvent)
            }
            trackpadView.addSubview(rotateButton)
            self.rotateButton = rotateButton
            
            addSubview(trackpadView)
            self.trackpadView = trackpadView
            
            updateTrackpadAlternativePositions()
        } else {
            trackpadView?.removeFromSuperview()
            lookUpButton?.removeFromSuperview()
            scrollButton?.removeFromSuperview()
            zoomButton?.removeFromSuperview()
            rotateButton?.removeFromSuperview()
        }
    }
    func updateTrackpadAlternativePositions() {
        let aw = max(actionNode?.transformedBounds?.cg.width ?? 0, 150)
        let w: CGFloat = 40.0, padding: CGFloat = 4.0
        let lookUpSize = NSSize(width: w, height: 40)
        let scrollSize = NSSize(width: w, height: 40)
        let zoomSize = NSSize(width: w, height: 100)
        let rotateSize = NSSize(width: w, height: 40)
        let h = lookUpSize.height + scrollSize.height + zoomSize.height + rotateSize.height + padding * 5
        let b = bounds
        
        lookUpButton?.frame = NSRect(x: padding,
                                     y: padding * 4 + rotateSize.height + zoomSize.height + scrollSize.height,
                                   width: lookUpSize.width,
                                   height: lookUpSize.height)
        scrollButton?.frame = NSRect(x: padding,
                                     y: padding * 3 + rotateSize.height + zoomSize.height,
                                   width: scrollSize.width,
                                   height: scrollSize.height)
        zoomButton?.frame = NSRect(x: padding,
                                   y: padding * 2 + rotateSize.height,
                                   width: zoomSize.width,
                                   height: zoomSize.height)
        rotateButton?.frame = NSRect(x: padding,
                                   y: padding,
                                   width: rotateSize.width,
                                   height: rotateSize.height)
        trackpadView?.frame = NSRect(x: b.width - aw - w - padding * 2,
                                     y: b.midY - h / 2,
                                     width: w + padding * 2,
                                     height: h)
    }
    
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func resignFirstResponder() -> Bool { true }
    
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: document.cursor.ns)
    }
    
    var isEnableMenuCommand = false {
        didSet {
            guard isEnableMenuCommand != oldValue else { return }
            document.isShownLastEditedSheet = isEnableMenuCommand
            document.isNoneCursor = isEnableMenuCommand
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(SubMTKView.importDocument(_:)):
            return document.isSelectedNoneCursor
            
        case #selector(SubMTKView.exportAsImage(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsImage4K(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsPDF(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsGIF(_:)):
            return document.isSelectedNoneCursor
            
        case #selector(SubMTKView.exportAsMovie(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsMovie4K(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsSound(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsLinearPCM(_:)):
            return document.isSelectedNoneCursor
            
        case #selector(SubMTKView.exportAsDocument(_:)):
            return document.isSelectedNoneCursor
        case #selector(SubMTKView.exportAsDocumentWithHistory(_:)):
            return document.isSelectedNoneCursor
            
        case #selector(SubMTKView.clearHistory(_:)):
            return document.isSelectedNoneCursor
            
        case #selector(SubMTKView.undo(_:)):
            if isEnableMenuCommand {
                if document.isEditingSheet {
                    if document.isSelectedNoneCursor {
                        return document.selectedSheetViewNoneCursor?.history.isCanUndo ?? false
                    }
                } else {
                    return document.history.isCanUndo
                }
            }
            return false
        case #selector(SubMTKView.redo(_:)):
            if isEnableMenuCommand {
                if document.isEditingSheet {
                    if document.isSelectedNoneCursor {
                        return document.selectedSheetViewNoneCursor?.history.isCanRedo ?? false
                    }
                } else {
                    return document.history.isCanRedo
                }
            }
            return false
        case #selector(SubMTKView.cut(_:)):
            return isEnableMenuCommand
                && document.isSelectedNoneCursor && document.isSelectedOnlyNoneCursor
        case #selector(SubMTKView.copy(_:)):
            return isEnableMenuCommand
                && document.isSelectedNoneCursor && document.isSelectedOnlyNoneCursor
        case #selector(SubMTKView.paste(_:)):
            return if isEnableMenuCommand
                && document.isSelectedNoneCursor {
                switch Pasteboard.shared.copiedObjects.first {
                case .picture, .planesValue: document.isEditingSheet
                case .copiedSheetsValue: !document.isEditingSheet
                default: false
                }
            } else {
                false
            }
        case #selector(SubMTKView.find(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor && document.isSelectedText
        case #selector(SubMTKView.changeToDraft(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor
                && !(document.selectedSheetViewNoneCursor?.model.picture.isEmpty ?? true)
        case #selector(SubMTKView.cutDraft(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor
                && !(document.selectedSheetViewNoneCursor?.model.draftPicture.isEmpty ?? true)
        case #selector(SubMTKView.makeFaces(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor
                && !(document.selectedSheetViewNoneCursor?.model.picture.lines.isEmpty ?? true)
        case #selector(SubMTKView.cutFaces(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor
                && !(document.selectedSheetViewNoneCursor?.model.picture.planes.isEmpty ?? true)
        case #selector(SubMTKView.changeToVerticalText(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor && document.isSelectedText
        case #selector(SubMTKView.changeToHorizontalText(_:)):
            return isEnableMenuCommand && document.isEditingSheet
                && document.isSelectedNoneCursor && document.isSelectedText
        
        case #selector(SubMTKView.shownActionList(_:)):
            menuItem.state = !isHiddenActionList ? .on : .off
        case #selector(SubMTKView.hiddenActionList(_:)):
            menuItem.state = isHiddenActionList ? .on : .off
            
        case #selector(SubMTKView.shownTrackpadAlternative(_:)):
            menuItem.state = isShownTrackpadAlternative ? .on : .off
        case #selector(SubMTKView.hiddenTrackpadAlternative(_:)):
            menuItem.state = !isShownTrackpadAlternative ? .on : .off
            
        default:
            break
        }
        return true
    }
    
    @objc func clearHistoryDatabase(_ sender: Any) {
        Task { @MainActor in
            let result = await document.rootNode
                .show(message: "Do you want to clear root history?".localized,
                      infomation: "You can’t undo this action. \nRoot history is what is used in \"Undo\", \"Redo\" or \"Select Version\" when in root operation, and if you clear it, you will not be able to return to the previous work.".localized,
                      okTitle: "Clear Root History".localized,
                      isSaftyCheck: true)
            switch result {
            case .ok:
                let progressPanel = ProgressPanel(message: "Clearing Root History".localized)
                self.document.rootNode.show(progressPanel)
                let task = Task.detached {
                    await self.document.clearHistory { (progress, isStop) in
                        if Task.isCancelled {
                            isStop = true
                            return
                        }
                        Task { @MainActor in
                            progressPanel.progress = progress
                        }
                    }
                    Task { @MainActor in
                        progressPanel.closePanel()
                    }
                }
                progressPanel.cancelHandler = { task.cancel() }
            case .cancel: break
            }
        }
    }
    
    func replacingDatabase(from url: URL) {
        @Sendable func replace(to toURL: URL, progressHandler: (Double, inout Bool) -> ()) throws {
            var stop = false
            
            progressHandler(0.5, &stop)
            if stop { return }
            
            guard toURL != url else { throw URL.readError }
            let fm = FileManager.default
            if fm.fileExists(atPath: toURL.path) {
                try fm.trashItem(at: toURL, resultingItemURL: nil)
            }
            try fm.copyItem(at: url, to: toURL)
            
            progressHandler(1, &stop)
            if stop { return }
        }
        
        document.syncSave()
        
        let toURL = document.url
        
        let progressPanel = ProgressPanel(message: String(format: "Replacing %@".localized, System.dataName))
        document.rootNode.show(progressPanel)
        let task = Task.detached {
            do {
                try replace(to: toURL) { (progress, isStop) in
                    if Task.isCancelled {
                        isStop = true
                        return
                    }
                    Task { @MainActor in
                        progressPanel.progress = progress
                    }
                }
                Task { @MainActor in
                    self.updateWithURL()
                    progressPanel.closePanel()
                }
            } catch {
                Task { @MainActor in
                    self.document.rootNode.show(error)
                    self.updateWithURL()
                    progressPanel.closePanel()
                }
            }
        }
        progressPanel.cancelHandler = { task.cancel() }
    }
    func replaceDatabase(from url: URL) {
        Task { @MainActor in
            let result = await document.rootNode
                .show(message: String(format: "Do you want to replace %@?".localized, System.dataName),
                      infomation: String(format: "You can’t undo this action. \n%1$@ is all the data written to this %2$@, if you replace %1$@ with new %1$@, all old %1$@ will be moved to the Trash.".localized, System.dataName, System.appName),
                      okTitle: String(format: "Replace %@".localized, System.dataName),
                      isSaftyCheck: true)
            switch result {
            case .ok: replacingDatabase(from: url)
            case .cancel: break
            }
        }
    }
    @objc func replaceDatabase(_ sender: Any) {
        Task { @MainActor in
            let result = await document.rootNode
                .show(message: String(format: "Do you want to replace %@?".localized, System.dataName),
                      infomation: String(format: "You can’t undo this action. \n%1$@ is all the data written to this %2$@, if you replace %1$@ with new %1$@, all old %1$@ will be moved to the Trash.".localized, System.dataName, System.appName),
                      okTitle: String(format: "Replace %@...".localized, System.dataName),
                      isSaftyCheck: document.url.allFileSize > 20*1024*1024)
            switch result {
            case .ok:
                let loadResult = await URL.load(prompt: "Replace".localized,
                                                fileTypes: [Document.FileType.rasendata,
                                                            Document.FileType.sksdata])
                switch loadResult {
                case .complete(let ioResults):
                    replacingDatabase(from: ioResults[0].url)
                case .cancel: break
                }
            case .cancel: break
            }
        }
    }
    
    @objc func exportDatabase(_ sender: Any) {
        Task { @MainActor in
            let url = document.url
            let result = await URL.export(name: "User", fileType: Document.FileType.rasendata,
                                          fileSizeHandler: { url.allFileSize })
            switch result {
            case .complete(let ioResult):
                document.syncSave()
                
                @Sendable func export(progressHandler: @Sendable (Double, inout Bool) -> ()) async throws {
                    var stop = false
                    
                    progressHandler(0.5, &stop)
                    if stop { return }
                    
                    guard url != ioResult.url else { throw URL.readError }
                    let fm = FileManager.default
                    if fm.fileExists(atPath: ioResult.url.path) {
                        try fm.removeItem(at: ioResult.url)
                    }
                    if fm.fileExists(atPath: url.path) {
                        try fm.copyItem(at: url, to: ioResult.url)
                    } else {
                        try fm.createDirectory(at: ioResult.url,
                                               withIntermediateDirectories: false)
                    }
                    
                    try ioResult.setAttributes()
                    
                    progressHandler(1, &stop)
                    if stop { return }
                }
                
                let progressPanel = ProgressPanel(message: String(format: "Exporting %@".localized, System.dataName))
                document.rootNode.show(progressPanel)
                let task = Task.detached {
                    do {
                        try await export { (progress, isStop) in
                            if Task.isCancelled {
                                isStop = true
                                return
                            }
                            Task { @MainActor in
                                progressPanel.progress = progress
                            }
                        }
                        Task { @MainActor in
                            progressPanel.closePanel()
                        }
                    } catch {
                        Task { @MainActor in
                            self.document.rootNode.show(error)
                            progressPanel.closePanel()
                        }
                    }
                }
                progressPanel.cancelHandler = { task.cancel() }
            case .cancel: break
            }
        }
    }
    
    @objc func resetDatabase(_ sender: Any) {
        Task { @MainActor in
            let result = await document.rootNode
                .show(message: String(format: "Do you want to reset the %@?".localized, System.dataName),
                      infomation: String(format: "You can’t undo this action. \n%1$@ is all the data written to this %2$@, if you reset %1$@, all %1$@ will be moved to the Trash.".localized, System.dataName, System.appName),
                      okTitle: String(format: "Reset %@".localized, System.dataName),
                      isSaftyCheck: document.url.allFileSize > 20*1024*1024)
            switch result {
            case .ok:
                @Sendable func reset(in url: URL, progressHandler: (Double, inout Bool) -> ()) throws {
                    var stop = false
                    
                    progressHandler(0.5, &stop)
                    if stop { return }
                    
                    let fm = FileManager.default
                    if fm.fileExists(atPath: url.path) {
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    }
                    
                    progressHandler(1, &stop)
                    if stop { return }
                }
                
                document.syncSave()
                
                let url = document.url
                
                let progressPanel = ProgressPanel(message: String(format: "Resetting %@".localized, System.dataName))
                self.document.rootNode.show(progressPanel)
                let task = Task.detached {
                    do {
                        try reset(in: url) { (progress, isStop) in
                            if Task.isCancelled {
                                isStop = true
                                return
                            }
                            Task { @MainActor in
                                progressPanel.progress = progress
                            }
                        }
                        Task { @MainActor in
                            self.updateWithURL()
                            progressPanel.closePanel()
                        }
                    } catch {
                        Task { @MainActor in
                            self.document.rootNode.show(error)
                            self.updateWithURL()
                            progressPanel.closePanel()
                        }
                    }
                }
                progressPanel.cancelHandler = { task.cancel() }
            case .cancel: break
            }
        }
    }
    
    @objc func shownActionList(_ sender: Any) {
        UserDefaults.standard.set(false, forKey: SubMTKView.isHiddenActionListKey)
        isHiddenActionList = false
    }
    @objc func hiddenActionList(_ sender: Any) {
        UserDefaults.standard.set(true, forKey: SubMTKView.isHiddenActionListKey)
        isHiddenActionList = true
    }
    
    @objc func shownTrackpadAlternative(_ sender: Any) {
        UserDefaults.standard.set(true, forKey: SubMTKView.isShownTrackpadAlternativeKey)
        isShownTrackpadAlternative = true
    }
    @objc func hiddenTrackpadAlternative(_ sender: Any) {
        UserDefaults.standard.set(false, forKey: SubMTKView.isShownTrackpadAlternativeKey)
        isShownTrackpadAlternative = false
    }
    
    @objc func importDocument(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Importer(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    
    @objc func exportAsImage(_ sender: Any) {
        document.isNoneCursor = true
        let editor = ImageExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsImage4K(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Image4KExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsPDF(_ sender: Any) {
        document.isNoneCursor = true
        let editor = PDFExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsGIF(_ sender: Any) {
        document.isNoneCursor = true
        let editor = GIFExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsMovie(_ sender: Any) {
        document.isNoneCursor = true
        let editor = MovieExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsMovie4K(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Movie4KExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsSound(_ sender: Any) {
        document.isNoneCursor = true
        let editor = SoundExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsLinearPCM(_ sender: Any) {
        document.isNoneCursor = true
        let editor = LinearPCMExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    
    @objc func exportAsDocument(_ sender: Any) {
        document.isNoneCursor = true
        let editor = DocumentWithoutHistoryExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func exportAsDocumentWithHistory(_ sender: Any) {
        document.isNoneCursor = true
        let editor = DocumentExporter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    
    @objc func clearHistory(_ sender: Any) {
        document.isNoneCursor = true
        let editor = HistoryCleaner(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    
    @objc func undo(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Undoer(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func redo(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Redoer(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func cut(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Cutter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func copy(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Copier(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func paste(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Paster(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func find(_ sender: Any) {
        document.isNoneCursor = true
        let editor = Finder(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func changeToDraft(_ sender: Any) {
        document.isNoneCursor = true
        let editor = DraftChanger(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func cutDraft(_ sender: Any) {
        document.isNoneCursor = true
        let editor = DraftCutter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func makeFaces(_ sender: Any) {
        document.isNoneCursor = true
        let editor = FacesMaker(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func cutFaces(_ sender: Any) {
        document.isNoneCursor = true
        let editor = FacesCutter(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func changeToVerticalText(_ sender: Any) {
        document.isNoneCursor = true
        let editor = VerticalTextChanger(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    @objc func changeToHorizontalText(_ sender: Any) {
        document.isNoneCursor = true
        let editor = HorizontalTextChanger(document)
        editor.send(inputKeyEventWith(.began))
        Sleep.start()
        editor.send(inputKeyEventWith(.ended))
        document.isNoneCursor = false
    }
    
//    @objc func startDictation(_ sender: Any) {
//    }
//    @objc func orderFrontCharacterPalette(_ sender: Any) {
//    }
    
    func updateWithURL() {
        document = Document(url: document.url)
        setupDocument()
        document.restoreDatabase()
        document.screenBounds = bounds.my
        document.drawableSize = drawableSize.my
        clearColor = document.backgroundColor.mtl
        draw()
    }
    
    func draw(in view: MTKView) {}
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        document.screenBounds = bounds.my
        document.drawableSize = size.my
        
        if !isHiddenActionList {
            func update(_ node: Node) {
                let b = document.screenBounds
                let w = b.maxX - (node.bounds?.maxX ?? 0)
                let h = b.midY - (node.bounds?.midY ?? 0)
                node.attitude.position = Point(w, h)
            }
            if let actionNode = sheetActionNode {
                update(actionNode)
            }
            if let actionNode = rootActionNode {
                update(actionNode)
            }
        }
        if isShownTrackpadAlternative {
            updateTrackpadAlternativePositions()
        }
        
        update()
    }
    
    var viewportBounds: Rect {
        Rect(x: 0, y: 0,
             width: Double(drawableSize.width),
             height: Double(drawableSize.height))
    }
    func viewportScale() -> Double {
        return document.worldToViewportTransform.absXScale
            * document.viewportToScreenTransform.absXScale
            * Double(drawableSize.width / self.bounds.width)
    }
    func viewportBounds(from transform: Transform, bounds: Rect) -> Rect {
        let dr = Rect(x: 0, y: 0,
                      width: Double(drawableSize.width),
                      height: Double(drawableSize.height))
        let scale = Double(drawableSize.width / self.bounds.width)
        let st = transform
            * document.viewportToScreenTransform
            * Transform(translationX: 0,
                        y: -document.screenBounds.height)
            * Transform(scaleX: scale, y: -scale)
        return dr.intersection(bounds * st) ?? dr
    }
    
    func screenPoint(with event: NSEvent) -> NSPoint {
        convertToLayer(convert(event.locationInWindow, from: nil))
    }
    var screenPointFromCursor: NSPoint {
        guard let window = window else {
            return NSPoint()
        }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        return convertToLayer(convert(windowPoint, from: nil))
    }
    var clippedScreenPointFromCursor: NSPoint {
        guard let window = window else {
            return NSPoint()
        }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let b = NSRect(origin: NSPoint(), size: window.frame.size)
        if b.contains(windowPoint) {
            return convertToLayer(convert(windowPoint, from: nil))
        } else {
            let wp = NSPoint(x: b.midX, y: b.midY)
            return convertToLayer(convert(wp, from: nil))
        }
    }
    func convertFromTopScreen(_ p: NSPoint) -> NSPoint {
        guard let window = window else {
            return NSPoint()
        }
        let windowPoint = window
            .convertFromScreen(NSRect(origin: p, size: NSSize())).origin
        return convertToLayer(convert(windowPoint, from: nil))
    }
    func convertToTopScreen(_ r: NSRect) -> NSRect {
        guard let window = window else {
            return NSRect()
        }
        return window.convertToScreen(convert(convertFromLayer(r), to: nil))
    }
    func convertToTopScreen(_ p: NSPoint) -> NSPoint {
        convertToTopScreen(NSRect(origin: p, size: CGSize())).origin
    }
    
    override func mouseEntered(with event: NSEvent) {}
    override func mouseExited(with event: NSEvent) {
        document.stopScrollEvent()
    }
    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.mouseEnteredAndExited,
                                                    .mouseMoved,
                                                    .activeWhenFirstResponder],
                                          owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
    
    func dragEventWith(indicate nsEvent: NSEvent) -> DragEvent {
        DragEvent(screenPoint: screenPoint(with: nsEvent).my,
                  time: nsEvent.timestamp,
                  pressure: 1, phase: .changed)
    }
    func dragEventWith(_ nsEvent: NSEvent, _ phase: Phase) -> DragEvent {
        DragEvent(screenPoint: screenPoint(with: nsEvent).my,
                  time: nsEvent.timestamp,
                  pressure: Double(nsEvent.pressure), phase: phase)
    }
    func pinchEventWith(_ nsEvent: NSEvent, _ phase: Phase) -> PinchEvent {
        PinchEvent(screenPoint: screenPoint(with: nsEvent).my,
                   time: nsEvent.timestamp,
                   magnification: Double(nsEvent.magnification), phase: phase)
    }
    func scrollEventWith(_ nsEvent: NSEvent, _ phase: Phase,
                         touchPhase: Phase?,
                         momentumPhase: Phase?) -> ScrollEvent {
        let sdp = NSPoint(x: nsEvent.scrollingDeltaX,
                          y: -nsEvent.scrollingDeltaY).my
        let nsdp = Point(sdp.x.clipped(min: -500, max: 500),
                         sdp.y.clipped(min: -500, max: 500))
        return ScrollEvent(screenPoint: screenPoint(with: nsEvent).my,
                           time: nsEvent.timestamp,
                           scrollDeltaPoint: nsdp,
                           phase: phase,
                           touchPhase: touchPhase,
                           momentumPhase: momentumPhase)
    }
    func rotateEventWith(_ nsEvent: NSEvent,
                         _ phase: Phase) -> RotateEvent {
        RotateEvent(screenPoint: screenPoint(with: nsEvent).my,
                    time: nsEvent.timestamp,
                    rotationQuantity: Double(nsEvent.rotation), phase: phase)
    }
    func inputKeyEventWith(_ phase: Phase) -> InputKeyEvent {
        return InputKeyEvent(screenPoint: screenPointFromCursor.my,
                             time: ProcessInfo.processInfo.systemUptime,
                             pressure: 1, phase: phase, isRepeat: false,
                             inputKeyType: .click)
    }
    func inputKeyEventWith(at sp: Point, _ keyType: InputKeyType = .click,
                           _ phase: Phase) -> InputKeyEvent {
        InputKeyEvent(screenPoint: sp,
                      time: ProcessInfo.processInfo.systemUptime,
                      pressure: 1, phase: phase, isRepeat: false,
                      inputKeyType: keyType)
    }
    func inputKeyEventWith(_ nsEvent: NSEvent, _ keyType: InputKeyType,
                           isRepeat: Bool = false,
                           _ phase: Phase) -> InputKeyEvent {
        InputKeyEvent(screenPoint: screenPointFromCursor.my,
                      time: nsEvent.timestamp,
                      pressure: 1, phase: phase, isRepeat: isRepeat,
                      inputKeyType: keyType)
    }
    func inputKeyEventWith(drag nsEvent: NSEvent,
                           _ phase: Phase) -> InputKeyEvent {
        InputKeyEvent(screenPoint: screenPoint(with: nsEvent).my,
                      time: nsEvent.timestamp,
                      pressure: Double(nsEvent.pressure),
                      phase: phase, isRepeat: false,
                      inputKeyType: .click)
    }
    func inputKeyEventWith(_ dragEvent: DragEvent,
                           _ phase: Phase) -> InputKeyEvent {
        InputKeyEvent(screenPoint: dragEvent.screenPoint,
                      time: dragEvent.time,
                      pressure: dragEvent.pressure,
                      phase: phase, isRepeat: false,
                      inputKeyType: .click)
    }
    func inputTextEventWith(_ nsEvent: NSEvent, _ keyType: InputKeyType,
                            _ phase: Phase) -> InputTextEvent {
        InputTextEvent(screenPoint: screenPointFromCursor.my,
                       time: nsEvent.timestamp,
                       pressure: 1, phase: phase, isRepeat: nsEvent.isARepeat,
                       inputKeyType: keyType,
                       ns: nsEvent, inputContext: inputContext)
    }
    
    private var isOneFlag = false, oneFlagTime: Double?
    override func flagsChanged(with nsEvent: NSEvent) {
        let oldModifierKeys = document.modifierKeys
        
        document.modifierKeys = nsEvent.modifierKeys
        
        if oldModifierKeys.isEmpty && document.modifierKeys.isOne {
            isOneFlag = true
            oneFlagTime = nsEvent.timestamp
        } else if let oneKey = oldModifierKeys.oneInputKeyTYpe,
                  document.modifierKeys.isEmpty && isOneFlag,
            let oneFlagTime, nsEvent.timestamp - oneFlagTime < 0.175 {
            document.inputKey(inputKeyEventWith(nsEvent, oneKey, .began))
            document.inputKey(inputKeyEventWith(nsEvent, oneKey, .ended))
            isOneFlag = false
        } else {
            isOneFlag = false
        }
    }
    
    override func mouseMoved(with nsEvent: NSEvent) {
        document.indicate(with: dragEventWith(indicate: nsEvent))
        
        if let oldEvent = document.oldInputKeyEvent,
           let editor = document.inputKeyEditor {
            
            editor.send(inputKeyEventWith(nsEvent, oldEvent.inputKeyType, .changed))
        }
    }
    
    override func keyDown(with nsEvent: NSEvent) {
        isOneFlag = false
        guard let key = nsEvent.key else { return }
        let phase: Phase = nsEvent.isARepeat ? .changed : .began
        if key.isTextEdit
            && !document.modifierKeys.contains(.command)
            && document.modifierKeys != .control
            && document.modifierKeys != [.control, .option]
            && !document.modifierKeys.contains(.function) {
            
            document.inputText(inputTextEventWith(nsEvent, key, phase))
        } else {
            document.inputKey(inputKeyEventWith(nsEvent, key,
                                                isRepeat: nsEvent.isARepeat,
                                                phase))
        }
    }
    override func keyUp(with nsEvent: NSEvent) {
        guard let key = nsEvent.key else { return }
        let textEvent = inputTextEventWith(nsEvent, key, .ended)
        if document.oldInputTextKeys.contains(textEvent.inputKeyType) {
            document.inputText(textEvent)
        }
        if document.oldInputKeyEvent?.inputKeyType == key {
            document.inputKey(inputKeyEventWith(nsEvent, key, .ended))
        }
    }
    
    private var beganDragEvent: DragEvent?,
                oldPressureStage = 0, isDrag = false, isStrongDrag = false,
                firstTime = 0.0, firstP = Point(), isMovedDrag = false
    override func mouseDown(with nsEvent: NSEvent) {
        isOneFlag = false
        isDrag = false
        isStrongDrag = false
        let beganDragEvent = dragEventWith(nsEvent, .began)
        self.beganDragEvent = beganDragEvent
        oldPressureStage = 0
        firstTime = beganDragEvent.time
        firstP = beganDragEvent.screenPoint
        isMovedDrag = false
    }
    override func mouseDragged(with nsEvent: NSEvent) {
        guard let beganDragEvent = beganDragEvent else { return }
        let dragEvent = dragEventWith(nsEvent, .changed)
        guard dragEvent.screenPoint.distance(firstP) >= 2.5
            || dragEvent.time - firstTime >= 0.1 else { return }
        isMovedDrag = true
        if !isDrag {
            isDrag = true
            if oldPressureStage == 2 {
                isStrongDrag = true
                document.strongDrag(beganDragEvent)
            } else {
                document.drag(beganDragEvent)
            }
        }
        if isStrongDrag {
            document.strongDrag(dragEventWith(nsEvent, .changed))
        } else {
            document.drag(dragEventWith(nsEvent, .changed))
        }
    }
    override func mouseUp(with nsEvent: NSEvent) {
        let endedDragEvent = dragEventWith(nsEvent, .ended)
        if isDrag {
            if isStrongDrag {
                document.strongDrag(endedDragEvent)
                isStrongDrag = false
            } else {
                document.drag(endedDragEvent)
            }
            isDrag = false
        } else {
            if oldPressureStage >= 2 {
                quickLook(with: nsEvent)
            } else {
                guard let beganDragEvent = beganDragEvent else { return }
                if isMovedDrag {
                    document.drag(beganDragEvent)
                    document.drag(endedDragEvent)
                } else {
                    document.inputKey(inputKeyEventWith(beganDragEvent, .began))
                    Sleep.start()
                    document.inputKey(inputKeyEventWith(beganDragEvent, .ended))
                }
            }
        }
        beganDragEvent = nil
    }
    
    override func pressureChange(with event: NSEvent) {
        oldPressureStage = max(event.stage, oldPressureStage)
    }
    
    private var beganSubDragEvent: DragEvent?, isSubDrag = false, isSubTouth = false
    override func rightMouseDown(with nsEvent: NSEvent) {
        isOneFlag = false
        isSubTouth = nsEvent.subtype == .touch
        isSubDrag = false
        let beganDragEvent = dragEventWith(nsEvent, .began)
        self.beganSubDragEvent = beganDragEvent
    }
    override func rightMouseDragged(with nsEvent: NSEvent) {
        guard let beganDragEvent = beganSubDragEvent else { return }
        if !isSubDrag {
            isSubDrag = true
            document.subDrag(beganDragEvent)
        }
        document.subDrag(dragEventWith(nsEvent, .changed))
    }
    override func rightMouseUp(with nsEvent: NSEvent) {
        let endedDragEvent = dragEventWith(nsEvent, .ended)
        if isSubDrag {
            document.subDrag(endedDragEvent)
            isSubDrag = false
        } else {
            guard let beganDragEvent = beganSubDragEvent else { return }
            if beganDragEvent.screenPoint != endedDragEvent.screenPoint {
                document.subDrag(beganDragEvent)
                document.subDrag(endedDragEvent)
            } else {
                showMenu(nsEvent)
            }
        }
        if isSubTouth {
            oldScrollPosition = nil
        }
        isSubTouth = false
        beganSubDragEvent = nil
    }
    
    private var menuEditor: Exporter?
    func showMenu(_ nsEvent: NSEvent) {
        guard window?.sheets.isEmpty ?? false else { return }
        guard window?.isMainWindow ?? false else { return }
        
        let event = inputKeyEventWith(drag: nsEvent, .began)
        document.updateLastEditedSheetpos(from: event)
        let menu = NSMenu()
        if menuEditor != nil {
            menuEditor?.editor.end()
        }
        menuEditor = Exporter(document)
        menuEditor?.send(event)
        menu.delegate = self
        menu.addItem(SubNSMenuItem(title: "Import...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = Importer(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(SubNSMenuItem(title: "Export as Image...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = ImageExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as 4K Image...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = Image4KExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as PDF...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = PDFExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as GIF...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = GIFExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(SubNSMenuItem(title: "Export as Movie...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = MovieExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as 4K Movie...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = Movie4KExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as Sound...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = SoundExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as Linear PCM...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = LinearPCMExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(SubNSMenuItem(title: "Export as Document...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = DocumentWithoutHistoryExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(SubNSMenuItem(title: "Export as Document with History...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = DocumentExporter(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(SubNSMenuItem(title: "Clear History...".localized, closure: { [weak self] in
            guard let self else { return }
            let editor = HistoryCleaner(self.document)
            editor.send(self.inputKeyEventWith(drag: nsEvent, .began))
            editor.send(self.inputKeyEventWith(drag: nsEvent, .ended))
        }))
        
//        menu.addItem(SubNSMenuItem(title: "test".localized, closure: { [weak self] in
//            guard let self else { return }
//            self.isEnabledPinch = !self.isEnabledPinch
//            self.isEnabledScroll = !self.isEnabledScroll
//            self.isEnabledRotate = !self.isEnabledRotate
//        }))
        
        document.stopAllEvents()
        NSMenu.popUpContextMenu(menu, with: nsEvent, for: self)
    }
    func menuDidClose(_ menu: NSMenu) {
        menuEditor?.editor.end()
        menuEditor = nil
    }
    
    private var beganMiddleDragEvent: DragEvent?, isMiddleDrag = false
    override func otherMouseDown(with nsEvent: NSEvent) {
        isOneFlag = false
        isMiddleDrag = false
        let beganDragEvent = dragEventWith(nsEvent, .began)
        self.beganMiddleDragEvent = beganDragEvent
    }
    override func otherMouseDragged(with nsEvent: NSEvent) {
        guard let beganDragEvent = beganMiddleDragEvent else { return }
        if !isMiddleDrag {
            isMiddleDrag = true
            document.middleDrag(beganDragEvent)
        }
        document.middleDrag(dragEventWith(nsEvent, .changed))
    }
    override func otherMouseUp(with nsEvent: NSEvent) {
        let endedDragEvent = dragEventWith(nsEvent, .ended)
        if isMiddleDrag {
            document.middleDrag(endedDragEvent)
            isMiddleDrag = false
        } else {
            guard let beganDragEvent = beganSubDragEvent else { return }
            if beganDragEvent.screenPoint != endedDragEvent.screenPoint {
                document.middleDrag(beganDragEvent)
                document.middleDrag(endedDragEvent)
            }
        }
        beganMiddleDragEvent = nil
    }
    
    let scrollEndSec = 0.1
    private var scrollTask: Task<(), any Error>?
    override func scrollWheel(with nsEvent: NSEvent) {
        guard !isEnabledScroll else { return }
        
        func beginEvent() -> Phase {
            if scrollTask != nil {
                scrollTask?.cancel()
                scrollTask = nil
                return .changed
            } else {
                return .began
            }
        }
        func endEvent() {
            scrollTask = Task {
                try await Task.sleep(sec: scrollEndSec)
                try Task.checkCancellation()
                
                var event = scrollEventWith(nsEvent, .ended, touchPhase: nil, momentumPhase: nil)
                event.screenPoint = screenPointFromCursor.my
                event.time += scrollEndSec
                document.scroll(event)
                
                scrollTask = nil
            }
        }
        if nsEvent.phase.contains(.began) {
            allScrollPosition = .init()
            document.scroll(scrollEventWith(nsEvent, beginEvent(),
                                            touchPhase: .began,
                                            momentumPhase: nil))
        } else if nsEvent.phase.contains(.ended) {
            document.scroll(scrollEventWith(nsEvent, .changed,
                                            touchPhase: .ended,
                                            momentumPhase: nil))
            endEvent()
        } else if nsEvent.phase.contains(.changed) {
            var event = scrollEventWith(nsEvent, .changed,
                                        touchPhase: .changed,
                                        momentumPhase: nil)
            var dp = event.scrollDeltaPoint
            allScrollPosition += dp
            switch snapScrollType {
            case .x:
                if abs(allScrollPosition.y) < 5 {
                    dp.y = 0
                } else {
                    snapScrollType = .none
                }
            case .y:
                if abs(allScrollPosition.x) < 5 {
                    dp.x = 0
                } else {
                    snapScrollType = .none
                }
            case .none: break
            }
            event.scrollDeltaPoint = dp
            
            document.scroll(event)
        } else {
            if nsEvent.momentumPhase.contains(.began) {
                var event = scrollEventWith(nsEvent, beginEvent(),
                                            touchPhase: nil,
                                            momentumPhase: .began)
                var dp = event.scrollDeltaPoint
                switch snapScrollType {
                case .x: dp.y = 0
                case .y: dp.x = 0
                case .none: break
                }
                event.scrollDeltaPoint = dp
                document.scroll(event)
            } else if nsEvent.momentumPhase.contains(.ended) {
                var event = scrollEventWith(nsEvent, .changed,
                                            touchPhase: nil,
                                            momentumPhase: .ended)
                var dp = event.scrollDeltaPoint
                switch snapScrollType {
                case .x: dp.y = 0
                case .y: dp.x = 0
                case .none: break
                }
                event.scrollDeltaPoint = dp
                document.scroll(event)
                endEvent()
            } else if nsEvent.momentumPhase.contains(.changed) {
                var event = scrollEventWith(nsEvent, .changed,
                                            touchPhase: nil,
                                            momentumPhase: .changed)
                var dp = event.scrollDeltaPoint
                switch snapScrollType {
                case .x: dp.y = 0
                case .y: dp.x = 0
                case .none: break
                }
                event.scrollDeltaPoint = dp
                document.scroll(event)
            }
        }
    }
    
    var oldTouchPoints = [TouchID: Point]()
    var touchedIDs = [TouchID]()
    
    var isEnabledScroll = true
    var isEnabledPinch = true
    var isEnabledRotate = true
    var isEnabledSwipe = true
    var isEnabledPlay = true
    
    var isBeganScroll = false, oldScrollPosition: Point?, allScrollPosition = Point()
    var isBeganPinch = false, oldPinchDistance: Double?
    var isBeganRotate = false, oldRotateAngle: Double?
    var isPreparePlay = false
    var scrollVs = [(dp: Point, time: Double)]()
    var pinchVs = [(d: Double, time: Double)]()
    var rotateVs = [(d: Double, time: Double)]()
    var lastScrollDeltaPosition = Point()
    enum  SnapScrollType {
        case none, x, y
    }
    var snapScrollType = SnapScrollType.none
    var lastMagnification = 0.0
    var lastRotationQuantity = 0.0
    var isBeganSwipe = false, swipePosition: Point?
    
    private var scrollTimeValue = 0.0
    private var scrollTimer: (any DispatchSourceTimer)?
    private var pinchTimeValue = 0.0
    private var pinchTimer: (any DispatchSourceTimer)?
    
    struct TouchID: Hashable {
        var id: any NSCopying & NSObjectProtocol
        
        static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.id.isEqual(rhs.id)
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(id.hash)
        }
    }
    func touchPoints(with event: NSEvent) -> [TouchID: Point] {
        let touches = event.touches(matching: .touching, in: self)
        return touches.reduce(into: [TouchID: Point]()) {
            $0[.init(id: $1.identity)] =
            Point(Double($1.normalizedPosition.x * $1.deviceSize.width),
                  Double($1.normalizedPosition.y * $1.deviceSize.height))
        }
    }
    override func touchesBegan(with event: NSEvent) {
        let ps = touchPoints(with: event)
        oldTouchPoints = ps
        touchedIDs = Array(ps.keys)
        if ps.count == 2 {
            swipePosition = nil
            let ps0 = ps[touchedIDs[0]]!, ps1 = ps[touchedIDs[1]]!
            oldPinchDistance = ps0.distance(ps1)
            oldRotateAngle = ps0.angle(ps1)
            oldScrollPosition = ps0.mid(ps1)
            isBeganPinch = false
            isBeganScroll = false
            isBeganRotate = false
            snapScrollType = .none
            lastScrollDeltaPosition = .init()
            lastMagnification = 0
            pinchVs = []
            scrollVs = []
            rotateVs = []
        } else if ps.count == 3 {
            oldPinchDistance = nil
            oldRotateAngle = nil
            oldScrollPosition = nil
            
            isBeganSwipe = false
            swipePosition = Point()
        } else if ps.count == 4 {
            oldPinchDistance = nil
            oldRotateAngle = nil
            oldScrollPosition = nil
            
            oldScrollPosition = (0 ..< 4).map { ps[touchedIDs[$0]]! }.mean()!
            isPreparePlay = true
        }
    }
    override func touchesMoved(with event: NSEvent) {
        let ps = touchPoints(with: event)
        if ps.count == 2 {
            if touchedIDs.count == 2,
                isEnabledPinch || isEnabledScroll,
                let oldPinchDistance, let oldRotateAngle,
                let oldScrollPosition,
                let ps0 = ps[touchedIDs[0]],
                let ps1 = ps[touchedIDs[1]],
                let ops0 = oldTouchPoints[touchedIDs[0]],
                let ops1 = oldTouchPoints[touchedIDs[1]] {
               
                let nps0 = ps0.mid(ops0), nps1 = ps1.mid(ops1)
                let nPinchDistance = nps0.distance(nps1)
                let nRotateAngle = nps0.angle(nps1)
                let nScrollPosition = nps0.mid(nps1)
                if isEnabledPinch
                    && !isBeganScroll && !isBeganPinch && !isBeganRotate
                    && abs(Edge(ops0, ps0).angle(Edge(ops1, ps1))) > .pi / 2
                    && abs(nPinchDistance - oldPinchDistance) > 6
                    && nScrollPosition.distance(oldScrollPosition) <= 5 {
                    
                    isBeganPinch = true
                    
                    scrollTimer?.cancel()
                    scrollTimer = nil
                    pinchTimer?.cancel()
                    pinchTimer = nil
                    document.pinch(.init(screenPoint: screenPoint(with: event).my,
                                         time: event.timestamp,
                                         magnification: 0,
                                         phase: .began))
                    pinchVs.append((0, event.timestamp))
                    self.oldPinchDistance = nPinchDistance
                    lastMagnification = 0
                } else if isBeganPinch {
                    let magnification = (nPinchDistance - oldPinchDistance) * 0.0125
                    document.pinch(.init(screenPoint: screenPoint(with: event).my,
                                         time: event.timestamp,
                                         magnification: magnification.mid(lastMagnification),
                                         phase: .changed))
                    pinchVs.append((magnification, event.timestamp))
                    self.oldPinchDistance = nPinchDistance
                    lastMagnification = magnification
                } else if isEnabledScroll && !(isSubDrag && isSubTouth)
                            && !isBeganScroll && !isBeganPinch
                            && !isBeganRotate
                            && abs(nPinchDistance - oldPinchDistance) <= 6
                            && nScrollPosition.distance(oldScrollPosition) > 5 {
                    isBeganScroll = true
                    
                    scrollTimer?.cancel()
                    scrollTimer = nil
                    pinchTimer?.cancel()
                    pinchTimer = nil
                    document.scroll(.init(screenPoint: screenPoint(with: event).my,
                                          time: event.timestamp,
                                          scrollDeltaPoint: .init(),
                                          phase: .began,
                                          touchPhase: .began,
                                          momentumPhase: nil))
                    scrollVs.append((.init(), event.timestamp))
                    self.oldScrollPosition = nScrollPosition
                    lastScrollDeltaPosition = .init()
                    let dp = nScrollPosition - oldScrollPosition
                    snapScrollType = min(abs(dp.x), abs(dp.y)) < 3
                        ? (abs(dp.x) > abs(dp.y) ? .x : .y) : .none
                    
                    allScrollPosition = .init()
                } else if isBeganScroll {
                    var dp = nScrollPosition - oldScrollPosition
                    allScrollPosition += dp
                    switch snapScrollType {
                    case .x:
                        if abs(allScrollPosition.y) < 5 {
                            dp.y = 0
                        } else {
                            snapScrollType = .none
                        }
                    case .y:
                        if abs(allScrollPosition.x) < 5 {
                            dp.x = 0
                        } else {
                            snapScrollType = .none
                        }
                    case .none: break
                    }
                    let angle = dp.angle()
                    let dpl = dp.length() * 3.25
                    let length = dpl < 15 ? dpl : dpl
                        .clipped(min: 15, max: 200,
                                 newMin: 15, newMax: 500)
                    let scrollDeltaPosition = Point()
                        .movedWith(distance: length, angle: angle)
                    
                    document.scroll(.init(screenPoint: screenPoint(with: event).my,
                                          time: event.timestamp,
                                          scrollDeltaPoint: scrollDeltaPosition.mid(lastScrollDeltaPosition),
                                          phase: .changed,
                                          touchPhase: .changed,
                                          momentumPhase: nil))
                    scrollVs.append((scrollDeltaPosition, event.timestamp))
                    self.oldScrollPosition = nScrollPosition
                    lastScrollDeltaPosition = scrollDeltaPosition
                } else if isEnabledRotate
                            && !isBeganScroll && !isBeganPinch && !isBeganRotate
                            && nPinchDistance > 120
                            && abs(nPinchDistance - oldPinchDistance) <= 6
                            && nScrollPosition.distance(oldScrollPosition) <= 5
                            && abs(nRotateAngle.differenceRotation(oldRotateAngle)) > .pi * 0.02 {
                    
                    isBeganRotate = true
                    
                    scrollTimer?.cancel()
                    scrollTimer = nil
                    pinchTimer?.cancel()
                    pinchTimer = nil
                    document.rotate(.init(screenPoint: screenPoint(with: event).my,
                                         time: event.timestamp,
                                         rotationQuantity: 0,
                                         phase: .began))
                    self.oldRotateAngle = nRotateAngle
                    lastRotationQuantity = 0
                } else if isBeganRotate {
                    let rotationQuantity = nRotateAngle.differenceRotation(oldRotateAngle) * 80
                    document.rotate(.init(screenPoint: screenPoint(with: event).my,
                                          time: event.timestamp,
                                          rotationQuantity: rotationQuantity.mid(lastRotationQuantity),
                                          phase: .changed))
                    self.oldRotateAngle = nRotateAngle
                    lastRotationQuantity = rotationQuantity
                }
            }
        } else if ps.count == 3 {
            if touchedIDs.count == 3,
               isEnabledSwipe, let swipePosition,
               let ps0 = ps[touchedIDs[0]],
               let ops0 = oldTouchPoints[touchedIDs[0]],
               let ps1 = ps[touchedIDs[1]],
               let ops1 = oldTouchPoints[touchedIDs[1]],
               let ps2 = ps[touchedIDs[2]],
               let ops2 = oldTouchPoints[touchedIDs[2]] {
                
                let deltaP = [ps0 - ops0, ps1 - ops1, ps2 - ops2].sum()
                
                if !isBeganSwipe && abs(deltaP.x) > abs(deltaP.y) {
                    isBeganSwipe = true
                    
                    document.swipe(.init(screenPoint: screenPoint(with: event).my,
                                         time: event.timestamp,
                                         scrollDeltaPoint: Point(),
                                         phase: .began))
                    self.swipePosition = swipePosition + deltaP
                } else if isBeganSwipe {
                    document.swipe(.init(screenPoint: screenPoint(with: event).my,
                                         time: event.timestamp,
                                         scrollDeltaPoint: deltaP,
                                         phase: .changed))
                    self.swipePosition = swipePosition + deltaP
                }
            }
        } else if ps.count == 4 {
            let vs = (0 ..< 4).compactMap { ps[touchedIDs[$0]] }
            if let oldScrollPosition, vs.count == 4 {
                let np = vs.mean()!
                if np.distance(oldScrollPosition) > 5 {
                    isPreparePlay = false
                }
            }
        } else {
            if swipePosition != nil, isBeganSwipe {
                document.swipe(.init(screenPoint: screenPoint(with: event).my,
                                     time: event.timestamp,
                                     scrollDeltaPoint: Point(),
                                     phase: .ended))
                swipePosition = nil
                isBeganSwipe = false
            }
            
            endPinch(with: event)
            endRotate(with: event)
            endScroll(with: event)
        }
        
        oldTouchPoints = ps
    }
    override func touchesEnded(with event: NSEvent) {
        if oldTouchPoints.count == 4 {
            if isEnabledPlay && isPreparePlay {
                var event = inputKeyEventWith(event, .click, .began)
                event.inputKeyType = .control
                let player = Player(document)
                player.send(event)
                Sleep.start()
                event.phase = .ended
                player.send(event)
            }
        }
        
        if swipePosition != nil {
            document.swipe(.init(screenPoint: screenPoint(with: event).my,
                                 time: event.timestamp,
                                 scrollDeltaPoint: Point(),
                                 phase: .ended))
            swipePosition = nil
            isBeganSwipe = false
        }
        
        endPinch(with: event)
        endRotate(with: event)
        endScroll(with: event)
        
        oldTouchPoints = [:]
        touchedIDs = []
    }
    
    func endPinch(with event: NSEvent,
                  timeInterval: Double = 1 / 60) {
        guard isBeganPinch else { return }
        self.oldPinchDistance = nil
        isBeganPinch = false
        guard pinchVs.count >= 2 else { return }
        
        let fpi = pinchVs[..<(pinchVs.count - 1)]
            .lastIndex(where: { event.timestamp - $0.time > 0.05 }) ?? 0
        let lpv = pinchVs.last!
        let t = timeInterval + lpv.time
        
        let sd = pinchVs.last!.d
        let sign = sd < 0 ? -1.0 : 1.0
        let (a, b) = Double.leastSquares(xs: pinchVs[fpi...].map { $0.time },
                                         ys: pinchVs[fpi...].map { abs($0.d) })
        let v = min(a * t + b, 10)
        let tv = v / timeInterval
        let minTV = 0.01
        let sv = tv / (tv - minTV)
        if tv.isNaN || v < 0.04 || a == 0 {
            document.pinch(.init(screenPoint: screenPoint(with: event).my,
                                 time: event.timestamp,
                                 magnification: 0,
                                 phase: .ended))
        } else {
            pinchTimeValue = tv
            let screenPoint = screenPoint(with: event).my, time = event.timestamp
            pinchTimer = DispatchSource.scheduledTimer(withTimeInterval: timeInterval) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let ntv = self.pinchTimeValue * 0.8
                    self.pinchTimeValue = ntv
                    if ntv < minTV {
                        self.pinchTimer?.cancel()
                        self.pinchTimer = nil
                        self.pinchTimeValue = 0
                        
                        self.document.pinch(.init(screenPoint: screenPoint,
                                              time: time,
                                              magnification: 0,
                                              phase: .ended))
                    } else {
                        let m = timeInterval * (ntv - minTV) * sv * sign
                        self.document.pinch(.init(screenPoint: screenPoint,
                                              time: time,
                                              magnification: m,
                                              phase: .changed))
                    }
                }
            }
        }
    }
    func endRotate(with event: NSEvent) {
        guard isBeganRotate else { return }
        self.oldRotateAngle = nil
        isBeganRotate = false
        guard rotateVs.count >= 2 else { return }
        
        document.rotate(.init(screenPoint: screenPoint(with: event).my,
                             time: event.timestamp,
                             rotationQuantity: 0,
                             phase: .ended))
    }
    func endScroll(with event: NSEvent,
                   timeInterval: Double = 1 / 60) {
        guard isBeganScroll else { return }
        self.oldScrollPosition = nil
        isBeganScroll = false
        guard scrollVs.count >= 2 else { return }
        
        let fsi = scrollVs[..<(scrollVs.count - 1)]
            .lastIndex(where: { event.timestamp - $0.time > 0.05 }) ?? 0
        let lsv = scrollVs.last!
        let t = timeInterval + lsv.time
        
        let sdp = scrollVs.last!.dp
        let angle = sdp.angle()
        let (a, b) = Double.leastSquares(xs: scrollVs[fsi...].map { $0.time },
                            ys: scrollVs[fsi...].map { $0.dp.length() })
        let v = min(a * t + b, 700)
        let scale = v.clipped(min: 100, max: 700,
                              newMin: 0.9, newMax: 0.95)
        let tv = v / timeInterval
        let minTV = 100.0
        let sv = tv / (tv - minTV)
        if tv.isNaN || v < 5 || a == 0 {
            document.scroll(.init(screenPoint: screenPoint(with: event).my,
                                  time: event.timestamp,
                                  scrollDeltaPoint: .init(),
                                  phase: .ended,
                                  touchPhase: .ended,
                                  momentumPhase: nil))
        } else {
            document.scroll(.init(screenPoint: screenPoint(with: event).my,
                                  time: event.timestamp,
                                  scrollDeltaPoint: .init(),
                                  phase: .changed,
                                  touchPhase: .ended,
                                  momentumPhase: .began))
            
            scrollTimeValue = tv
            let screenPoint = screenPoint(with: event).my, time = event.timestamp
            scrollTimer = DispatchSource.scheduledTimer(withTimeInterval: timeInterval) { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let ntv = self.scrollTimeValue * scale
                    self.scrollTimeValue = ntv
                    let sdp = Point().movedWith(distance: timeInterval * (ntv - minTV) * sv,
                                                angle: angle)
                    if ntv < minTV {
                        self.scrollTimer?.cancel()
                        self.scrollTimer = nil
                        self.scrollTimeValue = 0
                        
                        self.document.scroll(.init(screenPoint: screenPoint,
                                              time: time,
                                              scrollDeltaPoint: .init(),
                                              phase: .ended,
                                              touchPhase: nil, momentumPhase: .ended))
                    } else {
                        self.document.scroll(.init(screenPoint: screenPoint,
                                              time: time,
                                              scrollDeltaPoint: sdp,
                                              phase: .changed,
                                              touchPhase: nil, momentumPhase: .changed))
                    }
                }
            }
        }
    }
    
    func cancelScroll(with event: NSEvent) {
        scrollTimer?.cancel()
        scrollTimer = nil
        
        guard isBeganScroll else { return }
        isBeganScroll = false
        document.scroll(.init(screenPoint: screenPoint(with: event).my,
                              time: event.timestamp,
                              scrollDeltaPoint: .init(),
                              phase: .ended,
                              touchPhase: .ended,
                              momentumPhase: nil))
        oldScrollPosition = nil
    }
    func cancelPinch(with event: NSEvent) {
        pinchTimer?.cancel()
        pinchTimer = nil
        
        guard isBeganPinch else { return }
        isBeganPinch = false
        document.pinch(.init(screenPoint: screenPoint(with: event).my,
                             time: event.timestamp,
                             magnification: 0,
                             phase: .ended))
        oldPinchDistance = nil
    }
    func cancelRotatte(with event: NSEvent) {
        guard isBeganRotate else { return }
        isBeganRotate = false
        document.rotate(.init(screenPoint: screenPoint(with: event).my,
                             time: event.timestamp,
                              rotationQuantity: 0,
                             phase: .ended))
        oldRotateAngle = nil
    }
    override func touchesCancelled(with event: NSEvent) {
        if swipePosition != nil {
            document.swipe(.init(screenPoint: screenPoint(with: event).my,
                                 time: event.timestamp,
                                 scrollDeltaPoint: .init(),
                                 phase: .ended))
            swipePosition = nil
            isBeganSwipe = false
        }
        
        cancelScroll(with: event)
        cancelRotatte(with: event)
        cancelPinch(with: event)
        
        oldTouchPoints = [:]
        touchedIDs = []
    }
    
    private enum TouchGesture {
        case none, pinch, rotate
    }
    private var blockGesture = TouchGesture.none
    override func magnify(with nsEvent: NSEvent) {
        guard !isEnabledPinch else { return }
        if nsEvent.phase.contains(.began) {
            blockGesture = .pinch
            pinchVs = []
            document.pinch(pinchEventWith(nsEvent, .began))
        } else if nsEvent.phase.contains(.ended) {
            blockGesture = .none
            document.pinch(pinchEventWith(nsEvent, .ended))
            pinchVs = []
        } else if nsEvent.phase.contains(.changed) {
            pinchVs.append((Double(nsEvent.magnification), nsEvent.timestamp))
            document.pinch(pinchEventWith(nsEvent, .changed))
        }
    }
    
    private var isFirstStoppedRotation = true
    private var isBlockedRotation = false
    private var rotatedValue: Float = 0.0
    private let blockRotationValue: Float = 4.0
    override func rotate(with nsEvent: NSEvent) {
        guard !isEnabledRotate else { return }
        if nsEvent.phase.contains(.began) {
            if blockGesture != .pinch {
                isBlockedRotation = false
                isFirstStoppedRotation = true
                rotatedValue = nsEvent.rotation
            } else {
                isBlockedRotation = true
            }
        } else if nsEvent.phase.contains(.ended) {
            if !isBlockedRotation {
                if !isFirstStoppedRotation {
                    isFirstStoppedRotation = true
                    document.rotate(rotateEventWith(nsEvent, .ended))
                }
            } else {
                isBlockedRotation = false
            }
        } else if nsEvent.phase.contains(.changed) {
            if !isBlockedRotation {
                rotatedValue += abs(nsEvent.rotation)
                if rotatedValue > blockRotationValue {
                    if isFirstStoppedRotation {
                        isFirstStoppedRotation = false
                        document.rotate(rotateEventWith(nsEvent, .began))
                    } else {
                        document.rotate(rotateEventWith(nsEvent, .changed))
                    }
                }
            }
        }
    }
    
    override func quickLook(with nsEvent: NSEvent) {
        guard window?.sheets.isEmpty ?? false else { return }
        
        document.inputKey(inputKeyEventWith(nsEvent, .lookUpTap, .began))
        Sleep.start()
        document.inputKey(inputKeyEventWith(nsEvent, .lookUpTap, .ended))
    }
    
    func windowLevel() -> Int {
        window?.level.rawValue ?? 0
    }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.markedClauseSegment, .glyphInfo]
    }
    func hasMarkedText() -> Bool {
        document.textEditor.editingTextView?.isMarked ?? false
    }
    func markedRange() -> NSRange {
        if let textView = document.textEditor.editingTextView,
           let range = textView.markedRange {
            return textView.model.string.nsRange(from: range)
                ?? NSRange(location: NSNotFound, length: 0)
        } else {
            return NSRange(location: NSNotFound, length: 0)
        }
    }
    func selectedRange() -> NSRange {
        if let textView = document.textEditor.editingTextView,
           let range = textView.selectedRange {
            return textView.model.string.nsRange(from: range)
                ?? NSRange(location: NSNotFound, length: 0)
        } else {
            return NSRange(location: NSNotFound, length: 0)
        }
    }
    func attributedString() -> NSAttributedString {
        if let text = document.textEditor.editingTextView?.model {
            return NSAttributedString(string: text.string.nsBased,
                                      attributes: text.typobute.attributes())
        } else {
            return NSAttributedString()
        }
    }
    func attributedSubstring(forProposedRange nsRange: NSRange,
                             actualRange: NSRangePointer?) -> NSAttributedString? {
        actualRange?.pointee = nsRange
        let attString = attributedString()
        if nsRange.location >= 0 && nsRange.upperBound <= attString.length {
            return attString.attributedSubstring(from: nsRange)
        } else {
            return nil
        }
    }
    func fractionOfDistanceThroughGlyph(for point: NSPoint) -> CGFloat {
        let p = convertFromTopScreen(point).my
        let d = document.textEditor.characterRatio(for: p)
        return CGFloat(d ?? 0)
    }
    func characterIndex(for nsP: NSPoint) -> Int {
        let p = convertFromTopScreen(nsP).my
        if let i = document.textEditor.characterIndex(for: p),
           let string = document.textEditor.editingTextView?.model.string {
            
            return string.nsIndex(from: i)
        } else {
            return 0
        }
    }
    func firstRect(forCharacterRange nsRange: NSRange,
                   actualRange: NSRangePointer?) -> NSRect {
        if let string = document.textEditor.editingTextView?.model.string,
           let range = string.range(fromNS: nsRange),
           let rect = document.textEditor.firstRect(for: range) {
            return convertToTopScreen(rect.cg)
        } else {
            return NSRect()
        }
    }
    func baselineDeltaForCharacter(at nsI: Int) -> CGFloat {
        if let string = document.textEditor.editingTextView?.model.string,
           let i = string.index(fromNS: nsI),
           let d = document.textEditor.baselineDelta(at: i) {
            
            return CGFloat(d)
        } else {
            return 0
        }
    }
    func drawsVerticallyForCharacter(at nsI: Int) -> Bool {
        if let o = document.textEditor.editingTextView?.textOrientation {
            return o == .vertical
        } else {
            return false
        }
    }
    
    func unmarkText() {
        document.textEditor.unmark()
    }
    
    func setMarkedText(_ str: Any,
                       selectedRange selectedNSRange: NSRange,
                       replacementRange replacementNSRange: NSRange) {
        guard let string = document.textEditor
                .editingTextView?.model.string else { return }
        let range = string.range(fromNS: replacementNSRange)
        
        func mark(_ mStr: String) {
            if let markingRange = mStr.range(fromNS: selectedNSRange) {
                document.textEditor.mark(mStr,
                                         markingRange: markingRange,
                                         at: range)
            }
        }
        if let attString = str as? NSAttributedString {
            mark(attString.string.swiftBased)
        } else if let nsString = str as? NSString {
            mark((nsString as String).swiftBased)
        }
    }
    func insertText(_ str: Any, replacementRange: NSRange) {
        guard let string = document.textEditor
                .editingTextView?.model.string else { return }
        let range = string.range(fromNS: replacementRange)
        
        if let attString = str as? NSAttributedString {
            document.textEditor.insert(attString.string.swiftBased,
                                       at: range)
        } else if let nsString = str as? NSString {
            document.textEditor.insert((nsString as String).swiftBased,
                                       at: range)
        }
    }
    
//    // control return
//    override func insertLineBreak(_ sender: Any?) {}
//    // option return
//    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {}
    override func insertNewline(_ sender: Any?) {
        document.textEditor.insertNewline()
    }
    override func insertTab(_ sender: Any?) {
        document.textEditor.insertTab()
    }
    override func deleteBackward(_ sender: Any?) {
        document.textEditor.deleteBackward()
    }
    override func deleteForward(_ sender: Any?) {
        document.textEditor.deleteForward()
    }
    override func moveLeft(_ sender: Any?) {
        document.textEditor.moveLeft()
    }
    override func moveRight(_ sender: Any?) {
        document.textEditor.moveRight()
    }
    override func moveUp(_ sender: Any?) {
        document.textEditor.moveUp()
    }
    override func moveDown(_ sender: Any?) {
        document.textEditor.moveDown()
    }
}
extension SubMTKView {
    override func draw(_ dirtyRect: NSRect) {
        autoreleasepool { self.render() }
    }
    func render() {
        guard let commandBuffer
                = Renderer.shared.commandQueue.makeCommandBuffer() else { return }
        guard let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable else {
            commandBuffer.commit()
            return
        }
        renderPassDescriptor.colorAttachments[0].texture = multisampleColorTexture
        renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
        renderPassDescriptor.stencilAttachment.texture = depthStencilTexture
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            let ctx = Context(encoder, renderstate)
            let wtvTransform = document.worldToViewportTransform
            let wtsScale = document.worldToScreenScale
            document.rootNode.draw(with: wtvTransform, scale: wtsScale, in: ctx)
            
            if isShownDebug || isShownClock {
                drawDebugNode(in: ctx)
            }
            if !isHiddenActionList {
                let t = document.screenToViewportTransform
                actionNode?.draw(with: t, scale: 1, in: ctx)
            }
            
            ctx.encoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    func drawDebugNode(in context: Context) {
        updateDebugCount += 1
        if updateDebugCount >= 10 {
            updateDebugCount = 0
            let size = Renderer.shared.device.currentAllocatedSize
            let debugGPUSize = Int(Double(size) / (1024 * 1024))
            let maxSize = Renderer.shared.device.recommendedMaxWorkingSetSize
            let debugMaxGPUSize = Int(Double(maxSize) / (1024 * 1024))
            let string0 = isShownClock ? "\(Date().defaultString)" : ""
            let string1 = isShownDebug ? "GPU Memory: \(debugGPUSize) / \(debugMaxGPUSize) MB" : ""
            debugNode.path = Text(string: string0 + (isShownClock && isShownDebug ? " " : "") + string1).typesetter.path()
        }
        let t = document.screenToViewportTransform
        debugNode.draw(with: t, scale: 1, in: context)
    }
}
typealias NodeOwner = SubMTKView

final class Context {
    fileprivate var encoder: any MTLRenderCommandEncoder
    fileprivate let rs: Renderstate
    
    fileprivate init(_ encoder: any MTLRenderCommandEncoder,
                     _ rs: Renderstate) {
        self.encoder = encoder
        self.rs = rs
    }
    
    func setVertex(_ buffer: Buffer, offset: Int = 0, at index: Int) {
        encoder.setVertexBuffer(buffer.mtl, offset: offset, index: index)
    }
    func setVertex(bytes: UnsafeRawPointer, length: Int, at index: Int) {
        encoder.setVertexBytes(bytes, length: length, index: index)
    }
    func setVertexCacheSampler(at index: Int) {
        encoder.setVertexSamplerState(rs.cacheSamplerState, index: index)
    }
    
    func setFragment(_ texture: Texture?, at index: Int) {
        encoder.setFragmentTexture(texture?.mtl, index: index)
    }
    
    @discardableResult
    func drawTriangle(start i: Int = 0, with counts: [Int]) -> Int {
        counts.reduce(into: i) {
            encoder.drawPrimitives(type: .triangle,
                                   vertexStart: $0, vertexCount: $1)
            $0 += $1
        }
    }
    @discardableResult
    func drawTriangleStrip(start i: Int = 0, with counts: [Int]) -> Int {
        counts.reduce(into: i) {
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: $0, vertexCount: $1)
            $0 += $1
        }
    }
    
    func clip(_ rect: Rect) {
        encoder.setScissorRect(MTLScissorRect(x: Int(rect.minX),
                                              y: Int(rect.minY),
                                              width: max(1, Int(rect.width)),
                                              height: max(1, Int(rect.height))))
    }
    
    func setOpaqueColorPipeline() {
        encoder.setRenderPipelineState(rs.opaqueColorRenderPipelineState)
    }
    func setAlphaColorPipeline() {
        encoder.setRenderPipelineState(rs.alphaColorRenderPipelineState)
    }
    func setColorsPipeline() {
        encoder.setRenderPipelineState(rs.colorsRenderPipelineState)
    }
    func setMaxColorsPipeline() {
        encoder.setRenderPipelineState(rs.maxColorsRenderPipelineState)
    }
    func setOpaqueTexturePipeline() {
        encoder.setRenderPipelineState(rs.opaqueTextureRenderPipelineState)
    }
    func setAlphaTexturePipeline() {
        encoder.setRenderPipelineState(rs.alphaTextureRenderPipelineState)
    }
    func setStencilPipeline() {
        encoder.setRenderPipelineState(rs.stencilRenderPipelineState)
    }
    func setStencilBezierPipeline() {
        encoder.setRenderPipelineState(rs.stencilBezierRenderPipelineState)
    }
    func setInvertDepthStencil() {
        encoder.setDepthStencilState(rs.invertDepthStencilState)
    }
    func setNormalDepthStencil() {
        encoder.setDepthStencilState(rs.normalDepthStencilState)
    }
    func setClippingDepthStencil() {
        encoder.setDepthStencilState(rs.clippingDepthStencilState)
    }
}

extension Node {
    func moveCursor(to sp: Point) {
        if let subMTKView = owner, let h = NSScreen.main?.frame.height {
            let np = subMTKView.convertToTopScreen(sp.cg)
            CGDisplayMoveCursorToPoint(0, CGPoint(x: np.x, y: h - np.y))
        }
    }
    func show(definition: String, font: Font, orientation: Orientation, at p: Point) {
        if let owner = owner {
            let attributes = Typobute(font: font,
                                      orientation: orientation).attributes()
            let attString = NSAttributedString(string: definition,
                                               attributes: attributes)
            let sp = owner.document.convertWorldToScreen(convertToWorld(p))
            owner.showDefinition(for: attString, at: sp.cg)
        }
    }
    
    func show(_ error: any Error) {
        guard let window = owner?.window else { return }
        NSAlert(error: error).beginSheetModal(for: window,
                                              completionHandler: { _ in })
    }
    
    func show(message: String = "", infomation: String = "", isCaution: Bool = false) {
        guard let window = owner?.window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = infomation
        if isCaution {
            alert.alertStyle = .critical
            alert.window.defaultButtonCell = nil
        }
        alert.beginSheetModal(for: window) { _ in }
    }
    
    enum AlertResult {
        case ok, cancel
    }
    @MainActor func show(message: String, infomation: String, okTitle: String,
                         isSaftyCheck: Bool = false,
                         isDefaultButton: Bool = false) async -> AlertResult {
        guard let window = owner?.window else { return .cancel }
        let alert = NSAlert()
        let okButton = alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: "Cancel".localized)
        alert.messageText = message
        if isSaftyCheck {
            okButton.isEnabled = false
            
            let textField = SubNSCheckbox(onTitle: "Enable the run button".localized,
                                          offTitle: "Disable the run button".localized) { [weak okButton] bool in
                okButton?.isEnabled = bool
            }
            alert.accessoryView = textField
        }
        alert.informativeText = infomation
        alert.alertStyle = .critical
        if !isDefaultButton {
            alert.window.defaultButtonCell = nil
        }
        let result = await alert.beginSheetModal(for: window)
        return switch result {
        case .alertFirstButtonReturn: .ok
        default: .cancel
        }
    }
    
    @MainActor func show(message: String, infomation: String, titles: [String]) async -> Int? {
        guard let window = owner?.window else { return nil }
        let alert = NSAlert()
        for title in titles {
            alert.addButton(withTitle: title)
        }
        alert.messageText = message
        alert.informativeText = infomation
        return await alert.beginSheetModal(for: window).rawValue
    }
    
    @MainActor func show(message: String, infomation: String) async {
        guard let window = owner?.window else { return }
        let alert = NSAlert()
        alert.addButton(withTitle: "Done".localized)
        alert.messageText = message
        alert.informativeText = infomation
        
        _ = await alert.beginSheetModal(for: window)
    }
    
    func show(_ progressPanel: ProgressPanel) {
        guard let window = owner?.window else { return }
        progressPanel.topWindow = window
        progressPanel.begin()
        window.beginSheet(progressPanel.window) { _ in }
    }
}

extension Node {
    func renderedTexture(with size: Size, backgroundColor: Color,
                         sampleCount: Int = 4, mipmapped: Bool = false) -> Texture? {
        guard let bounds = bounds else { return nil }
        return renderedTexture(in: bounds, to: size,
                               backgroundColor: backgroundColor,
                               sampleCount: sampleCount, mipmapped: mipmapped)
    }
    func renderedAntialiasFillImage(in bounds: Rect, to size: Size,
                                    backgroundColor: Color, _ colorSpace: ColorSpace) -> Image? {
        guard children.contains(where: { $0.fillType != nil }) else {
            return image(in: bounds, size: size, backgroundColor: backgroundColor, .sRGB)
        }
        
        children.forEach {
            if $0.lineType != nil {
                $0.isHidden = true
            }
        }
        guard let oImage = image(in: bounds, size: size * 2, backgroundColor: backgroundColor,
                                 colorSpace, isAntialias: false)?
            .resize(with: size) else { return nil }
        children.forEach {
            if $0.lineType != nil {
                $0.isHidden = false
            }
            if $0.fillType != nil {
                $0.isHidden = true
            }
        }
        fillType = nil
        guard let nImage = image(in: bounds, size: size, backgroundColor: nil, colorSpace) else { return nil }
        return oImage.drawn(nImage, in: Rect(size: size))
    }
    func renderedTexture(in bounds: Rect, to size: Size,
                         backgroundColor: Color,
                         sampleCount: Int = 4, mipmapped: Bool = false) -> Texture? {
        let transform = Transform(translation: -bounds.origin)
            * Transform(invertedViewportSize: bounds.size)
        return renderedTexture(to: size, transform: transform,
                               backgroundColor: backgroundColor,
                               sampleCount: sampleCount, mipmapped: mipmapped)
    }
    func renderedTexture(to size: Size, transform: Transform,
                         backgroundColor: Color,
                         sampleCount: Int = 4, mipmapped: Bool = false) -> Texture? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0 && height > 0 else { return nil }
        
        let renderer = Renderer.shared
        
        let renderstate: Renderstate
        if sampleCount == 8 && renderer.device.supportsTextureSampleCount(8) {
            if let aRenderstate = Renderstate.sampleCount8 {
                renderstate = aRenderstate
            } else {
                return nil
            }
        } else if sampleCount == 4 {
            if let aRenderstate = Renderstate.sampleCount4 {
                renderstate = aRenderstate
            } else {
                return nil
            }
        } else {
            if let aRenderstate = Renderstate.sampleCount1 {
                renderstate = aRenderstate
            } else {
                return nil
            }
        }
        
        let rpd: MTLRenderPassDescriptor, mtlTexture: any MTLTexture
        if sampleCount > 1 {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderer.pixelFormat,
                                                              width: width,
                                                              height: height,
                                                              mipmapped: mipmapped)
            guard let aMTLTexture
                    = renderer.device.makeTexture(descriptor: td) else { return nil }
            mtlTexture = aMTLTexture
            
            let msaatd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderer.pixelFormat,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
            msaatd.storageMode = .private
            msaatd.usage = .renderTarget
            msaatd.textureType = .type2DMultisample
            msaatd.sampleCount = renderstate.sampleCount
            guard let msaaTexture
                    = renderer.device.makeTexture(descriptor: msaatd) else { return nil }
            
            rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .multisampleResolve
            rpd.colorAttachments[0].clearColor = backgroundColor.mtl
            rpd.colorAttachments[0].texture = msaaTexture
            rpd.colorAttachments[0].resolveTexture = mtlTexture
        } else {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderer.pixelFormat,
                                                              width: width,
                                                              height: height,
                                                              mipmapped: mipmapped)
            td.usage = [.renderTarget, .shaderRead]
            guard let aMTLTexture
                    = renderer.device.makeTexture(descriptor: td) else { return nil }
            mtlTexture = aMTLTexture
            
            rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .store
            rpd.colorAttachments[0].clearColor = backgroundColor.mtl
            rpd.colorAttachments[0].texture = mtlTexture
        }
        
        let stencilD = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .stencil8,
                                                                width: width,
                                                                height: height,
                                                                mipmapped: false)
        stencilD.storageMode = .private
        stencilD.usage = .renderTarget
        if sampleCount > 1 {
            stencilD.textureType = .type2DMultisample
            stencilD.sampleCount = renderstate.sampleCount
        } else {
            stencilD.textureType = .type2D
        }
        guard let stencilMTLTexture = renderer.device.makeTexture(descriptor: stencilD) else { return nil }
        rpd.stencilAttachment.texture = stencilMTLTexture
        
        guard let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return nil }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        
        isRenderCache = false
        let ctx = Context(encoder, renderstate)
        draw(with: localTransform.inverted() * transform, in: ctx)
        ctx.encoder.endEncoding()
        isRenderCache = true
        
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()
        if mipmapped {
            blitCommandEncoder?.generateMipmaps(for: mtlTexture)
        } else {
            blitCommandEncoder?.synchronize(resource: mtlTexture)
        }
        blitCommandEncoder?.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return Texture(mtlTexture, isOpaque: backgroundColor.opacity == 1,
                       colorSpace: renderer.colorSpace)
    }
    
    func render(with size: Size, in pdf: PDF) {
        guard let bounds = bounds else { return }
        render(in: bounds, to: size, in: pdf)
    }
    func render(with size: Size, backgroundColor: Color, in pdf: PDF) {
        guard let bounds = bounds else { return }
        render(in: bounds, to: size,
               backgroundColor: backgroundColor, in: pdf)
    }
    func render(in bounds: Rect, to size: Size, in pdf: PDF) {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: size.width / bounds.width,
                        y: size.height / bounds.height)
        render(to: size, transform: transform, in: pdf)
    }
    func render(in bounds: Rect, to size: Size,
                backgroundColor: Color, in pdf: PDF) {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: size.width / bounds.width,
                        y: size.height / bounds.height)
        render(to: size, transform: transform,
               backgroundColor: backgroundColor, in: pdf)
    }
    func render(to size: Size, transform: Transform, in pdf: PDF) {
        let ctx = pdf.ctx
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        ctx.beginPDFPage(nil)
        
        if case .color(let backgroundColor) = fillType {
            ctx.setFillColor(backgroundColor.cg)
            ctx.fill(Rect(origin: Point(), size: size).cg)
        }
        ctx.concatenate(nt.cg)
        render(in: ctx)
        
        ctx.endPDFPage()
        ctx.restoreGState()
    }
    func render(to size: Size, transform: Transform,
                backgroundColor: Color, in pdf: PDF) {
        let ctx = pdf.ctx
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        ctx.beginPDFPage(nil)
        
        ctx.setFillColor(backgroundColor.cg)
        ctx.fill(Rect(origin: Point(), size: size).cg)
        ctx.concatenate(nt.cg)
        render(in: ctx)
        
        ctx.endPDFPage()
        ctx.restoreGState()
    }
    func render(in bounds: Rect, to toBounds: Rect, in pdf: PDF) {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: toBounds.width / bounds.width,
                        y: toBounds.height / bounds.height)
            * Transform(translation: toBounds.origin)
        let ctx = pdf.ctx
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        if case .color(let backgroundColor) = fillType {
            ctx.setFillColor(backgroundColor.cg)
            ctx.fill(toBounds.cg)
        }
        ctx.concatenate(nt.cg)
        render(in: ctx)
        ctx.restoreGState()
    }
    func render(in bounds: Rect, to toBounds: Rect,
                backgroundColor: Color, in pdf: PDF) {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: toBounds.width / bounds.width,
                        y: toBounds.height / bounds.height)
            * Transform(translation: toBounds.origin)
        let ctx = pdf.ctx
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        ctx.setFillColor(backgroundColor.cg)
        ctx.fill(toBounds.cg)
        ctx.concatenate(nt.cg)
        render(in: ctx)
        ctx.restoreGState()
    }
    
    func imageInBounds(size: Size? = nil,
                       backgroundColor: Color? = nil,
                       _ colorSpace: ColorSpace,
                       isAntialias: Bool = true,
                       isGray: Bool = false) -> Image? {
        guard let bounds = bounds else { return nil }
        return image(in: bounds, size: size ?? bounds.size,
                     backgroundColor: backgroundColor, colorSpace,
                     isAntialias: isAntialias, isGray: isGray)
    }
    func image(in bounds: Rect,
               size: Size,
               backgroundColor: Color? = nil, _ colorSpace: ColorSpace,
               isAntialias: Bool = true,
               isGray: Bool = false) -> Image? {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: size.width / bounds.width,
                        y: size.height / bounds.height)
        return image(size: size, transform: transform,
                     backgroundColor: backgroundColor, colorSpace,
                     isAntialias: isAntialias, isGray: isGray)
    }
    func image(size: Size, transform: Transform,
               backgroundColor: Color? = nil, _ colorSpace: ColorSpace,
               isAntialias: Bool = true,
               isGray: Bool = false) -> Image? {
        let ctx = context(size: size, transform: transform, backgroundColor: backgroundColor,
                          colorSpace, isAntialias: isAntialias, isGray: isGray)
        guard let cgImage = ctx?.makeImage() else { return nil }
        return Image(cgImage: cgImage)
    }
    func bitmap<Value: FixedWidthInteger & UnsignedInteger>(size: Size,
                                                            backgroundColor: Color? = nil,
                                                            _ colorSpace: ColorSpace,
                                                            isAntialias: Bool = true,
                                                            isGray: Bool = false) -> Bitmap<Value>? {
        guard let bounds = bounds else { return nil }
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: size.width / bounds.width,
                        y: size.height / bounds.height)
        guard let ctx = context(size: size, transform: transform,
                                backgroundColor: backgroundColor, colorSpace,
                                isAntialias: isAntialias, isGray: isGray) else { return nil }
        return .init(ctx)
    }
    private func context(size: Size, transform: Transform,
                         backgroundColor: Color? = nil, _ colorSpace: ColorSpace,
                         isAntialias: Bool = true,
                         isGray: Bool = false) -> CGContext? {
        guard let space = isGray ? CGColorSpaceCreateDeviceGray() : colorSpace.cg else { return nil }
        let ctx: CGContext
        if colorSpace.isHDR {
            let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            guard let actx = CGContext(data: nil,
                                      width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 32, bytesPerRow: 0, space: space,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            ctx = actx
        } else {
            let bitmapInfo = CGBitmapInfo(rawValue: isGray ? CGImageAlphaInfo.none.rawValue : (backgroundColor?.opacity == 1 ?
                                            CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue))
            guard let actx = CGContext(data: nil,
                                      width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            ctx = actx
        }
        
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        if let backgroundColor = backgroundColor {
            ctx.setFillColor(backgroundColor.cg)
            ctx.fill(Rect(origin: Point(), size: size).cg)
        } else if case .color(let backgroundColor)? = fillType {
            ctx.setFillColor(backgroundColor.cg)
            ctx.fill(Rect(origin: Point(), size: size).cg)
        }
        ctx.setShouldAntialias(isAntialias)
        ctx.concatenate(nt.cg)
        render(in: ctx)
        ctx.restoreGState()
        return ctx
    }
    func renderInBounds(size: Size? = nil, in ctx: CGContext) {
        guard let bounds = bounds else { return }
        render(in: bounds, size: size ?? bounds.size, in: ctx)
    }
    func render(in bounds: Rect, size: Size, in ctx: CGContext) {
        let transform = Transform(translation: -bounds.origin)
            * Transform(scaleX: size.width / bounds.width,
                        y: size.height / bounds.height)
        render(transform: transform, in: ctx)
    }
    func render(transform: Transform, in ctx: CGContext) {
        let nt = localTransform.inverted() * transform
        ctx.saveGState()
        ctx.concatenate(nt.cg)
        render(in: ctx)
        ctx.restoreGState()
    }
    func render(in ctx: CGContext) {
        guard !isHidden else { return }
        if !isIdentityFromLocal {
            ctx.saveGState()
            ctx.concatenate(localTransform.cg)
        }
        if let typesetter = path.typesetter, let b = bounds {
            if let lineType = lineType {
                switch lineType {
                case .color(let color):
                    ctx.saveGState()
                    ctx.setStrokeColor(color.cg)
                    ctx.setLineWidth(lineWidth)
                    ctx.setLineJoin(.round)
                    typesetter.append(in: ctx)
                    ctx.strokePath()
                    ctx.restoreGState()
                case .gradient: break
                }
            }
            switch fillType {
            case .color(let color):
                typesetter.draw(in: b, fillColor: color, in: ctx)
            default:
                typesetter.draw(in: b, fillColor: .content, in: ctx)
            }
        } else if !path.isEmpty {
            if let fillType = fillType {
                switch fillType {
                case .color(let color):
                    let cgPath = CGMutablePath()
                    for pathline in path.pathlines {
                        let polygon = pathline.polygon()
                        let points = polygon.points.map { $0.cg }
                        if !points.isEmpty {
                            cgPath.addLines(between: points)
                            cgPath.closeSubpath()
                        }
                    }
                    ctx.addPath(cgPath)
                    let cgColor = color.cg
                    if isCPUFillAntialias {
                        ctx.setFillColor(cgColor)
                        ctx.drawPath(using: .fill)
                    } else {
                        ctx.setShouldAntialias(false)
                        ctx.setFillColor(cgColor)
                        ctx.drawPath(using: .fill)
                        ctx.setShouldAntialias(true)
                    }
                case .gradient(let colors):
                    for ts in path.triangleStrips {
                        let rgbas = colors.map { $0.rgba.premultipliedAlpha }
                        let minCount = min(ts.points.count, rgbas.count)
                        if minCount >= 3 {
                            for i in 2 ..< minCount {
                                if i % 2 == 0 {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i],
                                              ts.points[i - 1]),
                                                           rgbas[i - 2], rgbas[i], rgbas[i - 1])
                                } else {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i - 1],
                                                                 ts.points[i]),
                                                           rgbas[i - 2], rgbas[i - 1], rgbas[i])
                                }
                            }
                        }
                    }
                case .maxGradient(let colors):
                    ctx.saveGState()
                    ctx.setBlendMode(.darken)
                    
                    for ts in path.triangleStrips {
                        let rgbas = colors.map { $0.rgba.premultipliedAlpha }
                        let minCount = min(ts.points.count, rgbas.count)
                        if minCount >= 3 {
                            for i in 2 ..< minCount {
                                if i % 2 == 0 {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i],
                                              ts.points[i - 1]),
                                                           rgbas[i - 2], rgbas[i], rgbas[i - 1])
                                } else {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i - 1],
                                                                 ts.points[i]),
                                                           rgbas[i - 2], rgbas[i - 1], rgbas[i])
                                }
                            }
                        }
                    }
                    
                    ctx.restoreGState()
                case .texture(let texture):
                    if let cgImage = texture.cgImage, let b = bounds {
                        ctx.draw(cgImage, in: b.cg)
                    }
                }
            }
            if let lineType = lineType {
                switch lineType {
                case .color(let color):
                    ctx.setFillColor(color.cg)
                    let (pd, counts) = path.outlinePointsDataWith(lineWidth: lineWidth)
                    var i = 0
                    let cgPath = CGMutablePath()
                    for count in counts {
                        let points = (i ..< (i + count)).map {
                            Point(Double(pd[$0 * 4]),
                                  Double(pd[$0 * 4 + 1])).cg
                        }
                        if !points.isEmpty {
                            cgPath.addLines(between: points)
                            cgPath.closeSubpath()
                        }
                        i += count
                    }
                    ctx.addPath(cgPath)
                    ctx.fillPath()
                case .gradient(let colors):
                    let (pd, counts) = path.linePointsDataWith(lineWidth: lineWidth)
                    let rgbas = path.lineColorsDataWith(colors, lineWidth: lineWidth)
                    var i = 0
                    for count in counts {
                        let points = (i ..< (i + count)).map {
                            Point(Double(pd[$0 * 4]),
                                  Double(pd[$0 * 4 + 1]))
                        }
                        let ts = TriangleStrip(points: points)
                        let minCount = min(ts.points.count, rgbas.count)
                        if minCount >= 3 {
                            for i in 2 ..< minCount {
                                if i % 2 == 0 {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i],
                                              ts.points[i - 1]),
                                                           rgbas[i - 2], rgbas[i], rgbas[i - 1])
                                } else {
                                    ctx.drawTriangleInData(.init(ts.points[i - 2], ts.points[i - 1],
                                                                 ts.points[i]),
                                                           rgbas[i - 2], rgbas[i - 1], rgbas[i])
                                }
                            }
                        }
                        
                        i += count
                    }
                }
            }
        }
        children.forEach { $0.render(in: ctx) }
        if !isIdentityFromLocal {
            ctx.restoreGState()
        }
    }
}

extension CGContext {
    func drawTriangleInData(_ triangle: Triangle, _ rgba0: RGBA, _ rgba1: RGBA, _ rgba2: RGBA) {
        let bounds = triangle.bounds.integral
        let area = triangle.area
        guard area > 0, let bitmap = Bitmap<UInt8>(width: Int(bounds.width), height: Int(bounds.height),
                                                   colorSpace: .sRGB) else { return }
            
        saveGState()
        
        let path = CGMutablePath()
        path.addLines(between: [triangle.p0.cg, triangle.p1.cg, triangle.p2.cg])
        path.closeSubpath()
        addPath(path)
        clip()
        
        let rArea = Float(1 / area)
        for y in bitmap.height.range {
            for x in bitmap.width.range {
                let p = Point(x, bitmap.height - y - 1) + bounds.origin
                let areas = triangle.subs(form: p).map { Float($0.area) }
                let r = (rgba0.r * areas[1] + rgba1.r * areas[2] + rgba2.r * areas[0]) * rArea
                let g = (rgba0.g * areas[1] + rgba1.g * areas[2] + rgba2.g * areas[0]) * rArea
                let b = (rgba0.b * areas[1] + rgba1.b * areas[2] + rgba2.b * areas[0]) * rArea
                let a = (rgba0.a * areas[1] + rgba1.a * areas[2] + rgba2.a * areas[0]) * rArea
                bitmap[x, y, 0] = UInt8(r.clipped(min: 0, max: 1) * Float(UInt8.max))
                bitmap[x, y, 1] = UInt8(g.clipped(min: 0, max: 1) * Float(UInt8.max))
                bitmap[x, y, 2] = UInt8(b.clipped(min: 0, max: 1) * Float(UInt8.max))
                bitmap[x, y, 3] = UInt8(a.clipped(min: 0, max: 1) * Float(UInt8.max))
            }
        }
            
        if let cgImage = bitmap.image?.cg {
            draw(cgImage, in: bounds.cg)
        }
        
        restoreGState()
    }
}

extension MTLDevice {
    func makeBuffer(_ values: [Float]) -> Buffer? {
        let size = values.count * MemoryLayout<Float>.stride
        if let mtlBuffer = makeBuffer(bytes: values,
                                      length: size,
                                      options: .storageModeManaged) {
            return Buffer(mtl: mtlBuffer)
        } else {
            return nil
        }
    }
    func makeBuffer(_ values: [RGBA]) -> Buffer? {
        let size = values.count * MemoryLayout<RGBA>.stride
        if let mtlBuffer = makeBuffer(bytes: values,
                                      length: size,
                                      options: .storageModeManaged) {
            return Buffer(mtl: mtlBuffer)
        } else {
            return nil
        }
    }
    func makeBuffer(_ value: RGBA) -> Buffer? {
        var value = value
        let size = MemoryLayout<RGBA>.stride
        if let mtlBuffer = makeBuffer(bytes: &value,
                                      length: size,
                                      options: .storageModeManaged) {
            return Buffer(mtl: mtlBuffer)
        } else {
            return nil
        }
    }
}

extension Color {
    var mtl: MTLClearColor {
        MTLClearColorMake(Double(rgba.r), Double(rgba.g),
                          Double(rgba.b), Double(rgba.a))
    }
}

struct Buffer {
    fileprivate let mtl: any MTLBuffer
}

struct Texture {
    static let maxWidth = 16384, maxHeight = 16384
    
    fileprivate let mtl: any MTLTexture
    let isOpaque: Bool
    let cgColorSpace: CGColorSpace
    var cgImage: CGImage? {
        try? mtl.cgImage(with: cgColorSpace)
    }
    
    fileprivate init(_ mtl: any MTLTexture, isOpaque: Bool, colorSpace: CGColorSpace) {
        self.mtl = mtl
        self.isOpaque = isOpaque
        self.cgColorSpace = colorSpace
    }
    
    struct TextureError: Error {
        var localizedDescription = ""
    }
    
    struct Block {
        struct Item {
            let providerData: Data, width: Int, height: Int, mipmapLevel: Int, bytesPerRow: Int
        }
        
        var items: [Item]
        var isMipmapped: Bool { items.count > 1 }
    }
    static func block(from record: Record<Image>, isMipmapped: Bool = false) throws -> Block {
        if let image = record.value {
            try Self.block(from: image, isMipmapped: isMipmapped)
        } else if let data = record.decodedData {
            try Self.block(from: data, isMipmapped: isMipmapped)
        } else {
            throw TextureError()
        }
    }
    static func block(from data: Data, isMipmapped: Bool = false) throws -> Block {
        guard let cgImageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw TextureError()
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            throw TextureError()
        }
        return try block(from: cgImage, isMipmapped: isMipmapped)
    }
    static func block(from image: Image, isMipmapped: Bool = false) throws -> Block {
        try block(from: image.cg, isMipmapped: isMipmapped)
    }
    static func block(from cgImage: CGImage, isMipmapped: Bool = false) throws -> Block {
        guard let dp = cgImage.dataProvider, let data = dp.data else { throw TextureError() }
        let iw = cgImage.width, ih = cgImage.height
        
        var items = [Block.Item(providerData: data as Data, width: iw, height: ih, mipmapLevel: 0,
                                bytesPerRow: cgImage.bytesPerRow)]
        if isMipmapped {
            var image = Image(cgImage: cgImage), level = 1, mipW = iw / 2, mipH = ih / 2
            while mipW >= 1 && mipH >= 1 {
                guard let aImage = image.resize(with: Size(width: mipW, height: mipH)) else { throw TextureError() }
                image = aImage
                let cgImage = image.cg
                guard let ndp = cgImage.dataProvider, let ndata = ndp.data else { throw TextureError() }
                items.append(.init(providerData: ndata as Data, width: mipW, height: mipH,
                                   mipmapLevel: level, bytesPerRow: cgImage.bytesPerRow))
                
                mipW /= 2
                mipH /= 2
                level += 1
            }
        }
        return .init(items: items)
    }
    
//    @MainActor
    init(imageData: Data,
         isMipmapped: Bool = false,
         isOpaque: Bool = true,
         _ colorSpace: ColorSpace = .sRGB, isBGR: Bool = false) throws {
        let block = try Self.block(from: imageData, isMipmapped: isMipmapped)
        try self.init(block: block, isOpaque: isOpaque, colorSpace, isBGR: isBGR)
    }
//    @MainActor
    init(image: Image,
         isMipmapped: Bool = false,
         isOpaque: Bool = true,
         _ colorSpace: ColorSpace = .sRGB, isBGR: Bool = false) throws {
        let block = try Self.block(from: image, isMipmapped: isMipmapped)
        try self.init(block: block, isOpaque: isOpaque, colorSpace, isBGR: isBGR)
    }
//    @MainActor
    init(cgImage: CGImage,
         isMipmapped: Bool = false,
         isOpaque: Bool = true,
         _ colorSpace: ColorSpace = .sRGB, isBGR: Bool = false) throws {
        let block = try Self.block(from: cgImage, isMipmapped: isMipmapped)
        try self.init(block: block, isOpaque: isOpaque, colorSpace, isBGR: isBGR)
    }
//    @MainActor
    init(block: Block,
                    isOpaque: Bool = true,
         _ colorSpace: ColorSpace = .sRGB, isBGR: Bool = false) throws {
        guard let cgColorSpace = colorSpace.cg, !block.items.isEmpty else { throw TextureError() }
        let format = if colorSpace.isHDR {
            MTLPixelFormat.bgr10_xr_srgb
        } else {
            isBGR ? Renderer.shared.pixelFormat : Renderer.shared.imagePixelFormat
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                          width: block.items[0].width,
                                                          height: block.items[0].height,
                                                          mipmapped: block.isMipmapped)
        guard let mtl = Renderer.shared.device.makeTexture(descriptor: td) else { throw TextureError() }
        
        for item in block.items {
            guard let bytes = CFDataGetBytePtr(item.providerData as CFData) else { throw TextureError() }
            let region = MTLRegionMake2D(0, 0, item.width, item.height)
            mtl.replace(region: region, mipmapLevel: item.mipmapLevel,
                        withBytes: bytes, bytesPerRow: item.bytesPerRow)
        }
        
        self.init(mtl, isOpaque: isOpaque, colorSpace: cgColorSpace)
    }
    
    @MainActor static func withGPU(block: Block,
                                   isOpaque: Bool,
                                   _ colorSpace: ColorSpace = .sRGB,
                                   completionHandler: @escaping (Texture) -> ()) throws {
        guard let cgColorSpace = colorSpace.cg, !block.items.isEmpty else { throw TextureError() }
        let format = if colorSpace.isHDR {
            MTLPixelFormat.bgr10_xr_srgb
        } else {
            Renderer.shared.imagePixelFormat
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                          width: block.items[0].width,
                                                          height: block.items[0].height,
                                                          mipmapped: block.isMipmapped)
        guard let mtl = Renderer.shared.device.makeTexture(descriptor: td) else { return }
        
        for item in block.items {
            guard let bytes = CFDataGetBytePtr(item.providerData as CFData) else { throw TextureError() }
            let region = MTLRegionMake2D(0, 0, item.width, item.height)
            mtl.replace(region: region, mipmapLevel: item.mipmapLevel,
                        withBytes: bytes, bytesPerRow: item.bytesPerRow)
        }
        
        let commandQueue = Renderer.shared.commandQueue
        let commandBuffer = commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer?.makeBlitCommandEncoder()
        commandEncoder?.generateMipmaps(for: mtl)
        commandEncoder?.endEncoding()
        commandBuffer?.addCompletedHandler { _ in
            completionHandler(Texture(mtl, isOpaque: isOpaque, colorSpace: cgColorSpace))
        }
        commandBuffer?.commit()
    }
    
    @MainActor func with(mipmapLevel: Int) throws -> Self {
        let cgImage = try mtl.cgImage(with: cgColorSpace, mipmapLevel: mipmapLevel)
        let block = try Self.block(from: cgImage, isMipmapped: false)
        return try .init(block: block)
    }
}
extension Texture {
    static func mipmapLevel(from size: Size) -> Int {
        Int(Double.log2(max(size.width, size.height)).rounded(.down)) + 1
    }
    
    var size: Size {
        Size(width: mtl.width, height: mtl.height)
    }
    var isEmpty: Bool {
        size.isEmpty
    }
}
extension Texture {
    var image: Image? {
        if let cgImage = cgImage {
            Image(cgImage: cgImage)
        } else {
            nil
        }
    }
    func image(mipmapLevel: Int) -> Image? {
        if let cgImage = try? mtl.cgImage(with: cgColorSpace,
                                          mipmapLevel: mipmapLevel) {
            Image(cgImage: cgImage)
        } else {
            nil
        }
    }
}
extension Texture: Equatable {
    static func == (lhs: Texture, rhs: Texture) -> Bool {
        lhs.mtl === rhs.mtl
    }
}
extension MTLTexture {
    func cgImage(with colorSpace: CGColorSpace, mipmapLevel: Int = 0) throws -> CGImage {
        if pixelFormat != .rgba8Unorm && pixelFormat != .rgba8Unorm_srgb
            && pixelFormat != .bgra8Unorm && pixelFormat != .bgra8Unorm_srgb {
            throw Texture.TextureError(localizedDescription: "Texture: Unsupport pixel format \(pixelFormat)")
        }
        let nl = 2 ** mipmapLevel
        let nw = width / nl, nh = height / nl
        let bytesSize = nw * nh * 4
        guard let bytes = malloc(bytesSize) else {
            throw Texture.TextureError()
        }
        defer {
            free(bytes)
        }
        let bytesPerRow = nw * 4
        let region = MTLRegionMake2D(0, 0, nw, nh)
        getBytes(bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: mipmapLevel)
        
        let bitmapInfo = pixelFormat != .bgra8Unorm && pixelFormat != .bgra8Unorm_srgb ?
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue) :
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(dataInfo: nil, data: bytes, size: bytesSize,
                                            releaseData: { _, _, _ in }) else {
            throw Texture.TextureError()
        }
        guard let cgImage = CGImage(width: nw, height: nh,
                                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                    space: colorSpace, bitmapInfo: bitmapInfo, provider: provider,
                                    decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else {
            throw Texture.TextureError()
        }
        return cgImage
    }
}
extension CGContext {
    func renderedTexture(isOpaque: Bool) -> Texture? {
        if let cg = makeImage() {
            let mltTextureLoader = MTKTextureLoader(device: Renderer.shared.device)
            let option = MTKTextureLoader.Origin.flippedVertically
            if let mtl = try? mltTextureLoader.newTexture(cgImage: cg,
                                                          options: [.origin: option]) {
                return Texture(mtl, isOpaque: isOpaque,
                               colorSpace: Renderer.shared.colorSpace)
            }
        }
        return nil
    }
}

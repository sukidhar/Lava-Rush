//
//  GameScene.swift
//  Lava Rush
//
//  Created by Sukidhar Darisi on 21/04/21.
//


import UIKit
import QuartzCore
import SceneKit
import SpriteKit
import simd



struct BitMask : OptionSet{
    let rawValue: Int
    static let debris = BitMask(rawValue: 1 << 0)
    static let character = BitMask(rawValue: 1 << 1)
    static let collision = BitMask(rawValue: 1 << 2)
}


public extension CGFloat {
    
    // Converts degrees to radians
    func degreesToRadians() -> CGFloat {
        return CGFloat.pi * self / 180.0
    }
    
}
extension String{
    static let lsjump = "lsjump"
    static let rsjump = "rsjump"
    static let idle = "idle"
    static let worker = "worker"
    static let collider = "collider"
    static let armature = "MC3Armature"
    static let leftPlatform = "left platform"
    static let rightPlatform = "right platform"
    static let middlePlatform = "middle platform"
    static let planeCollider = "plane collider"
    static let none = ""
    static let tank = "tank"
    static let sphere = "sphere"
    
    func textToImage() -> UIImage? {
            let nsString = (self as NSString)
            let font = UIFont.systemFont(ofSize: 100) // you can change your font size here
            let stringAttributes = [NSAttributedString.Key.font: font]
            let imageSize = nsString.size(withAttributes: stringAttributes)

            UIGraphicsBeginImageContextWithOptions(imageSize, false, 0) //  begin image context
            UIColor.clear.set() // clear background
            UIRectFill(CGRect(origin: CGPoint(), size: imageSize)) // set rect size
            nsString.draw(at: CGPoint.zero, withAttributes: stringAttributes) // draw text within rect
            let image = UIGraphicsGetImageFromCurrentImageContext() // create image from context
            UIGraphicsEndImageContext() //  end image context

            return image ?? UIImage()
        }
}

enum JumpState{
    case shouldStart
    case willStart
    case ended
}

enum Sink {
    case shouldSink
    case willSink
    case end
}

enum Position{
    case leftEnd
    case rightEnd
    case center
    
    func description()->String{
        switch self {
        case .leftEnd:
            return "left"
        case .rightEnd:
            return "right"
        case .center:
            return "center"
        }
    }
}

struct SignConvention{
    let rawValue : Float
    
    static let positve = SignConvention(rawValue: 1)
    static let negative = SignConvention(rawValue: -1)
}

public class GameScene: SCNScene, SCNSceneRendererDelegate {
    //game state variables
    
    private var oxygenLevel : Double = 1
    private var overlayNode : OverlayProgressBar!
    private var deOxygenateRate : Double = 0.0015
    
    ///scn nodes
    private var positions = [Position.leftEnd,.center,.rightEnd]
    private var scnView : SCNView!
    private var scene : SCNScene!
    private var workerModel : SCNNode!
    private var workerArmature : SCNNode!
    
    private var animationPlayers = [String:SCNAnimationPlayer]()
    private var sinkTimer : Timer?
    private var sinkStatus = Sink.end

    private var leftPlatformNode : SCNNode!
    private var middlePlatformNode : SCNNode!
    private var rightPlatformNode : SCNNode!
    
    private var endColliderNode : SCNNode!
    private var tank : SCNNode!
    
    private var jumpState = JumpState.ended
    private var previousUpdateTime = 0.0
    private var currentCharacterPosition = Position.center
    private var recoverySpeed : Float = 0.05
    private var sinkSpeed : Float = 0.3
    
    private var platformNodes = [SCNNode]()
    

    
    func nodeForPosition(for pos : Position)->SCNNode{
        switch pos {
        case .center:
            return middlePlatformNode
        case .leftEnd:
            return leftPlatformNode
        case .rightEnd:
            return rightPlatformNode
            
        }
    }
    
    
    public init(view : SCNView) {
        super.init()
        setupScene(view: view)
        setUpNodes()
        setUpController()
        startGame()
    }
    
    private var collectSound : SCNAudioSource!
    
    func setupAudio(){
        if let ambience = SCNAudioSource(named: "art.scnassets/volcano.wav"){
            ambience.loops = true
            ambience.volume = 0.7
            ambience.isPositional = false
            ambience.shouldStream = true
            scene.rootNode.addAudioPlayer(SCNAudioPlayer(source: ambience))
        }
        
        if let sound = SCNAudioSource(named: "art.scnassets/collect.wav"){
            sound.loops = false
            sound.volume = 0.9
            sound.isPositional = false
            collectSound = sound
        }
    }
    
    
    func playSteamBuest(){
        let random = drand48() * 100
        if steamFrameCounter > 1200 + Int(random) {
            if let steam = SCNAudioSource(named: "art.scnassets/steamburst.wav"){
                steam.loops = false
                steam.volume = 0.6
                steam.isPositional = false
                self.scene.rootNode.addAudioPlayer(SCNAudioPlayer(source: steam))
                steamFrameCounter = 0
            }
        }
    }
    
    var steamFrameCounter = 0
    
    func randomPositionGenerator()->Position{
        let possiblePositions = positions.filter { (position) -> Bool in
            position != self.currentCharacterPosition
        }
        var partialArray = [Position]()
        let pos1 = possiblePositions[0]
        let pos2 = possiblePositions[1]
        if nodeForPosition(for: pos1).simdPosition.y < nodeForPosition(for: pos2).simdPosition.y{
            partialArray.append(contentsOf: [Position].init(repeating: pos1, count: 7))
            partialArray.append(contentsOf: [Position].init(repeating: pos2, count: 3))
        }else{
            partialArray.append(contentsOf: [Position].init(repeating: pos2, count: 7))
            partialArray.append(contentsOf: [Position].init(repeating: pos1, count: 3))
        }
        
        return partialArray.shuffled().randomElement()!
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupScene(view : SCNView){
        self.scnView = view
        scnView.delegate = self
        
        scene = SCNScene(named: "art.scnassets/MainScene.scn")!
        scnView.scene = scene
        scnView.preferredFramesPerSecond = 60
        scene.physicsWorld.contactDelegate = self
    }
    
    enum GameState {
        case willStart
        case started
        case paused
        case ended
    }
    
    private var gameState = GameState.willStart
    func endGame(){
        DispatchQueue.main.async {
            self.hideNodes()
            self.playDeathSound()
            self.gameState = .ended
            self.oxygenLevel = 1
            let skscn = SKScene(size: self.scnView.bounds.size)
            let end = SKSpriteNode(imageNamed: "art.scnassets/thank you.png")
            let center = self.scnView.center
            end.position = .init(x: center.x, y: center.y - 25)
            var aspectRatio = end.size.width/end.size.height
            end.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
            skscn.addChild(end)
            
            let tapToContinue = SKSpriteNode(imageNamed: "art.scnassets/taptocontinue.png")
            skscn.addChild(tapToContinue)
            tapToContinue.position = .init(x: center.x, y: center.y - 150)
            aspectRatio = tapToContinue.size.width/tapToContinue.size.height
            tapToContinue.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
            let repeataction = SKAction.sequence([.fadeAlpha(to: 0, duration: 0.5),.wait(forDuration: 2),.fadeAlpha(to: 1, duration: 0.5)])
            let action = SKAction.repeatForever(repeataction)
            tapToContinue.run(action)
            
            var imageName = ""
            switch self.deathCause{
            case .lava:
                imageName = "caughtFire.png"
            case .oxygen:
                imageName = "outOfOxygen.png"
            case .none:
                break
            }
            let deathImage = SKSpriteNode(imageNamed: "art.scnassets/\(imageName)")
            deathImage.position = .init(x: center.x, y: center.y + 150)
            aspectRatio = deathImage.size.width/deathImage.size.height
            deathImage.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
            skscn.addChild(deathImage)
            self.scnView.overlaySKScene = skscn
        }
    }
    
    func hideNodes(){
        leftPlatformNode.isHidden = true
        middlePlatformNode.isHidden = true
        rightPlatformNode.isHidden = true
        workerModel.isHidden = true
        tank.isHidden = true
    }
    
    func showNodes(){
        self.leftPlatformNode.isHidden = false
        self.rightPlatformNode.isHidden = false
        self.middlePlatformNode.isHidden = false
        self.tank.isHidden = false
        self.workerModel.isHidden = false
    }
    func resumegame(){
        DispatchQueue.main.async {
            self.showNodes()
            self.loadAnimations()
            self.workerModel.animationPlayer(forKey: .idle)?.play()
            self.fireSinkTimer()
            self.startIdleAnimation()
            self.setUpUI()
            self.gameState = .started
        }
    }
    func startGame(){
        DispatchQueue.main.async {
            self.generator.prepare()
            self.setupScene(view: self.scnView)
            self.setUpNodes()
            self.setUpController()
            if self.gameState == .willStart{
                self.showStartUpUI()
                self.setupAudio()
                self.hideNodes()
            }
            self.resetPositions()
        }
    }
    func showStartUpUI(){
        let skscn = SKScene(size: scnView.bounds.size)
        let welcomeTo = SKSpriteNode(imageNamed: "art.scnassets/welcome.png")
        let lavaRush = SKSpriteNode(imageNamed: "art.scnassets/logo.png")
        let center = scnView.center
        welcomeTo.position = .init(x: center.x, y: center.y+200)
        skscn.addChild(welcomeTo)
        var aspectRatio = welcomeTo.size.width/welcomeTo.size.height
        welcomeTo.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
        
        
        lavaRush.position = .init(x: center.x, y: center.y+50)
        aspectRatio = lavaRush.size.width/lavaRush
            .size.height
        lavaRush.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
        skscn.addChild(lavaRush)
        let tapToContinue = SKSpriteNode(imageNamed: "art.scnassets/taptocontinue.png")
        aspectRatio = tapToContinue.size.width/tapToContinue.size.height
        tapToContinue.size = .init(width: UIScreen.main.bounds.width - 50, height: (UIScreen.main.bounds.width - 50) / aspectRatio)
        let repeataction = SKAction.sequence([.fadeAlpha(to: 0, duration: 0.5),.wait(forDuration: 2),.fadeAlpha(to: 1, duration: 0.5)])
        let action = SKAction.repeatForever(repeataction)
        tapToContinue.run(action)
        tapToContinue.position = .init(x: center.x, y: center.y - 150)
        skscn.addChild(tapToContinue)
        scnView.overlaySKScene = skscn
    }
    
    
    func setUpUI(){
        self.overlayNode = OverlayProgressBar(value: oxygenLevel)
        overlayNode.position = .init(x: scnView.center.x-(UIScreen.main.bounds.width/2)+80, y:scnView.center.y + 250)
        let skscn = SKScene(size: scnView.bounds.size)
        skscn.addChild(overlayNode)
        self.scnView.overlaySKScene = skscn
    }
    
    func startIdleAnimation(){
        resetAnimation(withKey: .idle, for: workerModel)
        workerModel.animationPlayer(forKey: .idle)?.play()
    }
    
    final func invalidateSinkTimer(){
        self.sinkTimer?.invalidate()
        sinkTimer = nil
    }
    
    func fireSinkTimer(){
        self.invalidateSinkTimer()
        sinkTimer = .scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { [weak self](timer) in
            if self?.jumpState == .shouldStart || self?.jumpState == .willStart{
                self?.sinkStatus = .end
                timer.invalidate()
                return
            }
            self?.sinkStatus = .shouldSink
        })
    }
    
    func setUpController(){
        scnView.isMultipleTouchEnabled = false
        let singleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.sceneViewSingleTapped(recognizer:)))
        singleTapRecognizer.numberOfTapsRequired = 1
        self.scnView.addGestureRecognizer(singleTapRecognizer)
    }
    
    enum JumpType{
        case left
        case right
        case none
    }
    
    func resetPositions(){
        self.previousUpdateTime = 0
        self.oxygenLevel = 1
        self.leftPlatformNode.simdPosition.y = 0
        self.rightPlatformNode.simdPosition.y = 0
        self.middlePlatformNode.simdPosition.y = 0
        self.workerModel.simdPosition = workerModelInitPos!
        self.showTank()
        self.currentCharacterPosition = .center
        self.finalCharacterPosition = .center
        self.jumpFrameCount = 0
        self.jumpState = .ended
        self.jumpType = .none
        self.sinkStatus = .willSink
    }
    
    private var workerModelInitPos : SIMD3<Float>?
    private var jumpType = JumpType.none
    
    @objc func sceneViewSingleTapped(recognizer: UITapGestureRecognizer){
        let location = recognizer.location(in: self.scnView)
        if gameState == .willStart{
            resumegame()
            return
        }
        
        if gameState == .ended{
            self.gameState = .willStart
            startGame()
            return
        }
        
        let screenWidth = self.scnView.frame.width
        if jumpState == .shouldStart || jumpState == .willStart || jumpState != .ended{
            return
        }
        
        if location.x > screenWidth/2{
            jumpType = .left
        }else{
            jumpType = .right
        }
        if jumpType != .none{
            jumpState = .shouldStart
        }
        
    }
    
  
    
    
    
    func setUpNodes(){
        workerModel = scene.rootNode.childNode(withName: .worker, recursively: true)!
        if workerModelInitPos == nil{
            workerModelInitPos = workerModel.simdPosition
        }
        let collider = scene.rootNode.childNode(withName: .collider , recursively: true)!
        collider.physicsBody?.contactTestBitMask = BitMask.collision.rawValue
        workerArmature = scene.rootNode.childNode(withName: .armature, recursively: true)!
        leftPlatformNode = scene.rootNode.childNode(withName: .leftPlatform, recursively: true)!
        rightPlatformNode = scene.rootNode.childNode(withName: .rightPlatform, recursively: true)!
        middlePlatformNode = scene.rootNode.childNode(withName: .middlePlatform, recursively: true)!
        endColliderNode = scene.rootNode.childNode(withName: .planeCollider, recursively: true)!
        platformNodes = [leftPlatformNode,middlePlatformNode,rightPlatformNode]
        tank = scene.rootNode.childNode(withName: .tank, recursively: true)!
        
    }
    
    func showTank(){
        
        let action = SCNAction.fadeIn(duration: 0.3)
        let position = self.randomPositionGenerator()
        let node = self.nodeForPosition(for: position)
        self.tankPosition = position
        self.shouldShowTank = false
        tankFrameCounter = 0
        self.scene.rootNode.addChildNode(self.tank)
        self.tank.simdPosition = SIMD3<Float>(node.simdPosition.x, node.simdPosition.y + 0.7, node.simdPosition.z)
        self.tank.runAction(action)
        self.collidedWithOxygen = false
    }
    
    var tankPosition = Position.rightEnd
    var collidedWithOxygen = false
    var shouldShowTank = false
    var tankFrameCounter = 0
    
    func hideTank(){
        oxygenLevel += 0.95
        if oxygenLevel > 1{
            oxygenLevel = 1
        }
        if oxygenLevel < 0{
            oxygenLevel = 0
        }
        shouldShowTank = true
        tank.runAction(.fadeOut(duration: 0.1))
        tank.removeFromParentNode()
        if collectSound != nil{
            scene.rootNode.addAudioPlayer(SCNAudioPlayer(source: collectSound))
        }
    }
    
    
    func loadAnimations(){
        let idleAnimation = self.loadAnimation(fromSceneNamed: getCharacterAnimationSourceText(with: "characterIdle"))
        idleAnimation.stop()
        animationPlayers[.idle] = idleAnimation
        
        let leftShortJumpAnimation = self.loadAnimation(fromSceneNamed: getCharacterAnimationSourceText(with: "characterShortJumpL"))
        leftShortJumpAnimation.animation.repeatCount = 1
        leftShortJumpAnimation.animation.isRemovedOnCompletion = true
        leftShortJumpAnimation.stop()
        animationPlayers[.lsjump] = leftShortJumpAnimation
        
        let rightShortJumpAnimation = self.loadAnimation(fromSceneNamed: getCharacterAnimationSourceText(with: "characterShortJumpR"))
        rightShortJumpAnimation.animation.repeatCount = 1
        rightShortJumpAnimation.animation.isRemovedOnCompletion = true
        rightShortJumpAnimation.stop()
        animationPlayers[.rsjump] = rightShortJumpAnimation
        
        let action = SCNAction.repeatForever(SCNAction.rotate(by: .pi, around: SCNVector3(0, 0.5, 0), duration: 2))
        tank.runAction(action)
        
    }
    
    func resetAnimation(withKey key : String, for model : SCNNode){
        if let animationPlayer = animationPlayers[key]{
            model.addAnimationPlayer(animationPlayer, forKey: key)
        }
    }
    
    func getCharacterAnimationSourceText(with string : String) -> String{
        return "art.scnassets/\(string).scn"
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if gameState == .started{
            jump(for: renderer, updateAtTime: time )
        }
    }
    

    let generator = UIImpactFeedbackGenerator(style: .heavy)
    private var jumpFrameCount = Int.zero
    private var shouldCountFrames = true
    private var finalCharacterPosition = Position.center
    
    func jump(for renderer:SCNSceneRenderer, updateAtTime time : TimeInterval){
        
        if previousUpdateTime == 0.0 {
            previousUpdateTime = time
        }
        
        
        let deltaTime = time - previousUpdateTime
        let virtualFrameCount = Int(deltaTime / (1 / 60.0))
        previousUpdateTime = time
        
        var currentPosition = workerModel.simdPosition
        if jumpState == .shouldStart{
            if sinkStatus == .willSink || sinkStatus == .shouldSink{
                sinkStatus = .end
            }
            shouldCountFrames = false
            jumpState = .willStart
            var jumpAnimation : String = .none
            finalCharacterPosition = Position.center
            var signConvention = SignConvention.positve
            var jumpHeight : Float = 0
            switch currentCharacterPosition {
            case .leftEnd:
                switch jumpType {
                case .right:
                    jumpAnimation = .rsjump
                    signConvention = .positve
                    finalCharacterPosition = .center
                    
                    jumpHeight = middlePlatformNode.simdPosition.y - leftPlatformNode.simdPosition.y
                    
                case .left,.none:
                    jumpState = .ended
                }
            case .rightEnd:
                switch jumpType {
                case .right,.none:
                    jumpState = .ended
                case .left:
                    jumpAnimation = .lsjump
                    signConvention = .negative
                    finalCharacterPosition = .center
                    jumpHeight = middlePlatformNode.simdPosition.y - rightPlatformNode.simdPosition.y
                }
            case .center:
                switch jumpType {
                case .left:
                    jumpAnimation = .lsjump
                    signConvention = .negative
                    finalCharacterPosition = .leftEnd
                    
                    jumpHeight = leftPlatformNode.simdPosition.y - middlePlatformNode.simdPosition.y

                case .right:
                    jumpAnimation = .rsjump
                    signConvention = .positve
                    finalCharacterPosition = .rightEnd
                    
                    jumpHeight = rightPlatformNode.simdPosition.y - middlePlatformNode.simdPosition.y

                case .none:
                    jumpState = .ended
                }
            }
            if jumpState == .ended{
                self.sinkStatus = .shouldSink
                return
            }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            workerModel.animationPlayer(forKey: .idle)?.stop(withBlendOutDuration: 0.1)
            var events = [SCNAnimationEvent]()
            resetAnimation(withKey: jumpAnimation, for: workerModel)
            shouldCountFrames = true
            for e in 1...8
            {
                events.append(SCNAnimationEvent(keyTime: CGFloat(7+e)/60, block: { (_, _, _) in
                    self.workerModel.animationPlayer(forKey: jumpAnimation)?.speed = 1
                    currentPosition.z += Float(virtualFrameCount) / 8 * 0.9 * signConvention.rawValue
                    currentPosition.y += Float(virtualFrameCount) / 8 * (0.3 + jumpHeight/2)
                    self.workerModel.simdPosition = currentPosition
                }))
            }
            for e in 16..<28{
                events.append(SCNAnimationEvent(keyTime: CGFloat(e)/60, block: { (_, _, _) in
                    self.workerModel.animationPlayer(forKey: jumpAnimation)?.speed = 1
                    currentPosition.z += Float(virtualFrameCount) / 12 * 1.6 * signConvention.rawValue
                    currentPosition.y -= Float(virtualFrameCount) / 12 * (0.3 - jumpHeight/2)
                    self.workerModel.simdPosition = currentPosition
                }))
            }
            self.workerModel.animationPlayer(forKey: jumpAnimation)?.animation.animationEvents = events
            self.workerModel.animationPlayer(forKey: jumpAnimation)?.animation.animationDidStop = ({ (_, _, _) in
                self.jumpState = .ended
                self.jumpType = .none
                self.fireSinkTimer()
                self.currentCharacterPosition = self.finalCharacterPosition
                self.workerModel.animationPlayer(forKey: .idle)?.play()
            })
            self.workerModel.animationPlayer(forKey: jumpAnimation)?.play()
        }
        
        if jumpState == .ended && shouldShowTank{
            tankFrameCounter += 1
        }
        
        if tankFrameCounter > 180{
            showTank()
        }
        //lose oxygen
        if oxygenLevel <= 0.2{
            self.generator.impactOccurred()
        }
        oxygenLevel = oxygenLevel-(deOxygenateRate * Double(virtualFrameCount))
        
        if oxygenLevel <= 0 {
            deathCause = .oxygen
            endGame()
        }
        overlayNode.setValue(with: oxygenLevel)
        //decrease the height of the tile
        if  sinkStatus == .shouldSink {
            let node = nodeForPosition(for: currentCharacterPosition)
            let platformPosition = node.simdPosition
            let fallHeight : Float = sinkSpeed * Float(virtualFrameCount)/60
            workerModel.simdPosition = SIMD3(currentPosition.x, currentPosition.y-fallHeight, currentPosition.z)
            node.simdPosition = SIMD3(platformPosition.x, platformPosition.y-fallHeight, platformPosition.z)
        }
        
        // recover nodes
        if shouldCountFrames{
            jumpFrameCount += 1
        }else{
            jumpFrameCount = 0
        }
        
        let currentNode = nodeForPosition(for: currentCharacterPosition)
        let finalNode = nodeForPosition(for: finalCharacterPosition)
        
        for node in platformNodes{
            let raiseHeight = recoverySpeed * Float(virtualFrameCount)/60
            if jumpState == .willStart{
                if jumpFrameCount < 30{
                    continue
                }
                if node.name == finalNode.name{
                    continue
                }
                if node.simdPosition.y >= 0 {
                    node.simdPosition.y = 0
                    continue
                }else{
                    node.simdPosition.y += raiseHeight
                    if shouldShowTank && node.name == nodeForPosition(for: tankPosition).name{
                        tank.simdPosition.y += raiseHeight
                    }
                }
                continue
            }
            if jumpState == .ended{
                if node.name == currentNode.name{
                    continue
                }
                if node.simdPosition.y >= 0 {
                    node.simdPosition.y = 0
                    continue
                }else{
                    node.simdPosition.y += raiseHeight
                    if shouldShowTank && node.name == nodeForPosition(for: tankPosition).name{
                        tank.simdPosition.y += raiseHeight
                    }
                }
            }
        }
        
        // steam bursts
        
        steamFrameCounter += 1
        playSteamBuest()
    }
    
    func loadAnimation(fromSceneNamed sceneName: String) -> SCNAnimationPlayer {
        let scene = SCNScene( named: sceneName )!
        // find top level animation
        var animationPlayer: SCNAnimationPlayer! = nil
        scene.rootNode.enumerateChildNodes { (child, stop) in
            if !child.animationKeys.isEmpty {
                animationPlayer = child.animationPlayer(forKey: child.animationKeys[0])
                stop.pointee = true
            }
        }
        return animationPlayer
    }
    
    func playDeathSound(){
        if let death = SCNAudioSource(named: "art.scnassets/deathSound.mp3"){
            death.loops = false
            death.volume = 1
            death.isPositional = false
            self.scene.rootNode.addAudioPlayer(SCNAudioPlayer(source: death))
            steamFrameCounter = 0
        }
    }
    enum Death{
        case lava
        case oxygen
    }
    
    private var deathCause : Death!
}

extension GameScene : SCNPhysicsContactDelegate{
    enum CollisonType{
        case oxygen
        case gameOver
    }
    public func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        var collisonType : CollisonType
        if (contact.nodeB.name == .sphere && contact.nodeA.name == .collider) || (contact.nodeA.name == .sphere && contact.nodeB.name == .collider){
            collisonType = .oxygen
        }else{
            collisonType = .gameOver
        }
        
        if collisonType == .oxygen{
            handleOxygen()
        }
        else{
            deathCause = .lava
            handleGameOver()
        }
    }
    
    func handleOxygen(){
        if collidedWithOxygen{
            return
        }
        collidedWithOxygen = true
        hideTank()
    }
    
    func handleGameOver(){
        endGame()
    }
}

public class OverlayProgressBar: SKNode {
    
    // Visual settings
    public var radius: CGFloat = 90
    public var width: CGFloat = 12
    public var fontSize: CGFloat = 24
    
    
    private let circleNode = SKShapeNode(circleOfRadius: 0)
    private var healthNode : SKSpriteNode?
    
    // Sets or returns the value of the progress bar
    public var value: Double = 0
    private var startedAnimating = false
    
    public init(value : Double) {
        self.value = value
        super.init()
        if let heartImage = "❤️".textToImage(){
            let heartTexture = SKTexture(image: heartImage)
            self.healthNode = SKSpriteNode(texture: heartTexture)
        }
        // Full circle node in the background
        let backCircle = SKShapeNode(circleOfRadius: radius * 2)
        backCircle.lineWidth = width * 2
        backCircle.alpha = 0.5
        backCircle.strokeColor = .white
        circleNode.addChild(backCircle)

        // The arc circle displaying the current value
        circleNode.lineWidth = width * 2
        circleNode.strokeColor = .green
        addChild(circleNode)
        if healthNode != nil{
            addChild(healthNode!)
            healthNode?.setScale(1.75)
            healthNode?.position = .init(x: self.frame.midX, y: self.frame.midY)
        }
        setValue(with: self.value)
        // Smooth scaling (retina devices)
        setScale(0.25)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setValue(with newValue : Double){
        var setValue : Double = newValue
        if newValue > 1{
            setValue = 1
        }
            
        if newValue < 0{
            setValue = 0
        }
        self.value = setValue
        var strokeColor = UIColor.green
        if value > 0.80{
            strokeColor = .blue
        }else if value > 0.60{
            strokeColor = .green
        }else if value > 0.30{
            strokeColor = UIColor.red.withAlphaComponent(0.7)
        }else{
            strokeColor = .red
        }
        if !startedAnimating{
            if setValue < 0.20 && healthNode != nil{
                self.healthNode?.run(.sequence([.scale(by: 1.5, duration: 0.5),.scale(by: 0.75, duration: 0.5)]))
                startedAnimating = true
            }
        }
        if setValue > 0.2{
            healthNode?.setScale(1.75)
            startedAnimating = false
        }
        circleNode.path = UIBezierPath(
                        arcCenter: CGPoint(x: 0 , y: 0),
                        radius: radius * 2,
                        startAngle: CGFloat(90).degreesToRadians(),
                        endAngle: CGFloat(90 - 360 * value).degreesToRadians(),
                        clockwise: false)
                        .cgPath
        circleNode.strokeColor = strokeColor
    }
    
}


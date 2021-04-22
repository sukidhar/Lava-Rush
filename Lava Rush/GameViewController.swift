//
//  GameViewController.swift
//  Lava Rush
//
//  Created by Sukidhar Darisi on 21/04/21.
//

import UIKit
import QuartzCore
import SceneKit

class GameViewController: UIViewController {
    var gamescn : GameScene!
    override func viewDidLoad() {
        super.viewDidLoad()
        self.gamescn = GameScene(view: self.view as! SCNView)
        
        
    }
    
    func setUpController(){
        
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

}

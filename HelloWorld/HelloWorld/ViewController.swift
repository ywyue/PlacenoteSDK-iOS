//
//  ViewController.swift
//  HelloWorld
//
//  Created by Neil Mathew on 10/10/19.
//  Copyright © 2019 Placenote. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import PlacenoteSDK

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, PNDelegate {
  
  // UI View Panels
  @IBOutlet var sceneView: ARSCNView!             // Main AR Scene View
  @IBOutlet weak var mappingButtonPanel: UIView!  // Mapping Button Panel
  @IBOutlet weak var initPanel: UIView!           // Init Button Panel
  @IBOutlet weak var loadingButtonPanel: UIView!  // Loading Button Panel
  
  // UI Elements
  @IBOutlet weak var mapQualityProgress: UIProgressView!
  
  @IBOutlet var tapGestureRecognizer: UITapGestureRecognizer!
  @IBOutlet weak var saveButton: UIButton!
  
  @IBOutlet weak var statusLabel: UILabel!
  
  
  // Placenote variables
  private var camManager: CameraManager? = nil;
  private var ptViz: FeaturePointVisualizer? = nil;
  private var thumbnailSelector: LocalizationThumbnailSelector? = nil;
  
  private var minMapSize: Int = 200; // minimum map size we want to build
  
  private var objPosition: SCNVector3 = SCNVector3(0, 0, 0)
  
  private var mapQualityThresholdReached = false
    
  // View controller functions
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Set the view's delegate
    sceneView.delegate = self
    
    // Show statistics such as fps and timing information
    sceneView.showsStatistics = true
    
    // ARKit delegate setup
    sceneView.session.delegate = self
    
    // Placenote initialization setup
    
    // Set up this viqew controller as a delegate
    LibPlacenote.instance.multiDelegate += self
    
    //Set up placenote's camera manager
    if let camera: SCNNode = sceneView?.pointOfView {
      camManager = CameraManager(scene: sceneView.scene, cam: camera)
    }
    
    // Placenote feature visualization
    ptViz = FeaturePointVisualizer(inputScene: sceneView.scene);
    ptViz?.enablePointcloud()
    
    // A class that selects a localization thumbnail for a map
    thumbnailSelector = LocalizationThumbnailSelector();
    
    tapGestureRecognizer.isEnabled = false
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    // Create a session configuration
    let configuration = ARWorldTrackingConfiguration()
    
    sceneView.autoenablesDefaultLighting = true
    
    // Run the view's session
    sceneView.session.run(configuration)
    
    // Indicate to user that they can start mapping
    statusLabel.text = "Click New Map or Load Map"
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    
    // Pause the view's session
    sceneView.session.pause()
  }
  
  // Functions activated by buttons
  
  // New Map clicked
  @IBAction func StartMapping(_ sender: Any) {
    
    // check if placenote is initialized
    if (!LibPlacenote.instance.initialized()) {
      statusLabel.text = "Placenote is not initialized yet. Try again."
      return;
    }
    
    // hide init view and show mapping view
    initPanel.isHidden = true;
    
    // Prompt users on next step (add a model)
    statusLabel.text = "Point at a flat surface and tap the screen to add an object"
    tapGestureRecognizer.isEnabled = true
    
  }
  
  @IBAction func handleSceneTap(_ sender: UITapGestureRecognizer) {
    let tapLocation = sender.location(in: sceneView)
    let hitTestResults = sceneView.hitTest(tapLocation, types: .featurePoint)
    
    if let result = hitTestResults.first
    {
      print("hit test success")
      statusLabel.text = "Object added. Now scan the area around you and hit Save when you reach the minimum map size."
      
      // when using Placenote, any hit test with ARKit should be converted to Placenote frame
      let pose = LibPlacenote.instance.processPose(pose: result.worldTransform)
      objPosition = pose.position()
      placeObject(pos: objPosition)
      
      tapGestureRecognizer.isEnabled = false
      
        // Start the placenote mapping session
      LibPlacenote.instance.startSession()
      mappingButtonPanel.isHidden = false
      saveButton.isHidden = true
      
      mapQualityProgress.setProgress(0, animated: false)
    }
  }
  
  
  
  // Place a 3D model at hit position
    
  func placeObject(pos: SCNVector3) {
    let geometry:SCNGeometry = SCNSphere(radius: 0.05) //units, meters
    let geometryNode = SCNNode(geometry: geometry)
    geometryNode.position = pos
    geometryNode.name = "placedSphere"
    geometryNode.geometry?.firstMaterial?.diffuse.contents = UIColor.cyan
    sceneView.scene.rootNode.addChildNode(geometryNode)
  }
  
  
  // Save map button clicked
  @IBAction func saveMap(_ sender: Any) {
    mappingButtonPanel.isHidden = true;
    
    //save the map and stop session
    LibPlacenote.instance.saveMap(
      savedCb: { (mapID: String?) -> Void in
        print ("MapId: " + mapID!)
        
        // the best place to stop session is as soon as a mapID is received
        LibPlacenote.instance.stopSession()
        self.ptViz?.clearPointCloud() // clear the point cloud created so far
        
        // save mapid and object position in user defaults so we can load it with load map
        UserDefaults.standard.set(mapID, forKey: "mapId")
        let vectorArray = [self.objPosition.x, self.objPosition.y, self.objPosition.z]
        UserDefaults.standard.set(vectorArray, forKey: "objPosition")
        
        // delete the sphere
        self.sceneView.scene.rootNode.childNode(withName: "placedSphere", recursively: true)?.removeFromParentNode()
      },
      uploadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
        print("Map Uploading...")
        if(completed){
          self.statusLabel.text = "Map uploaded! You can now load the map and try relocalizing"
          
          // go back to home page, from where you can load the map
          self.initPanel.isHidden = false;
          
        }
        if (faulted) {
          print("Map upload failed.")
        }
        else {
          if (percentage < 0.99) {
            self.statusLabel.text = "Uploading Map: " + percentage.description + " %";
          }
        }
    })
  }
  
  // Load map button clicked from init panel
  @IBAction func loadMap(_ sender: Any) {
    // check if saved map exists
    let mapId = UserDefaults.standard.string(forKey: "mapId") ?? ""
    
    if (mapId == "")
    {
      self.statusLabel.text = "You have not saved a map yet. Nothing to load!"
      return
    }
    
    // get out of the init panel
    initPanel.isHidden = true
    
    LibPlacenote.instance.loadMap(mapId: mapId,
        downloadProgressCb: {(completed: Bool, faulted: Bool, percentage: Float) -> Void in
          if (completed) {
            self.statusLabel.text = "Map loaded. Point at your mapped area to relocalize the scene"
            LibPlacenote.instance.startSession()
          }
          else if (faulted) {
            self.statusLabel.text = "Map load failed. Check your API Key or your internet connection"
          }
          else {
            self.statusLabel.text = "Download map: " + percentage.description
          }
    })
    
  }
  
  
  
  // send AR frame to placenote
  func session(_ session: ARSession, didUpdate: ARFrame) {
    LibPlacenote.instance.setARFrame(frame: didUpdate)
  }
  
  // We use this call back to keep tracking map quality as you scan the area
  func onPose(_ outputPose: matrix_float4x4, _ arkitPose: matrix_float4x4) {
    
    if(LibPlacenote.instance.getMode() != LibPlacenote.MappingMode.mapping) {
      return
    }
    
    // get the size of the map that has been built so far
    let pointCloud: Array<PNFeaturePoint> = LibPlacenote.instance.getMap()
    if (pointCloud.count == 0) {
      return
    }
    
    // increment the progress bar
    let percentageMapped: Float = Float(pointCloud.count) / Float(minMapSize)
    mapQualityProgress.setProgress(percentageMapped, animated: true)
    
    // If the minimum map size is reached. Check whether the map quality threshold was hit
    if (percentageMapped >= 1.0)
    {
      if (mapQualityThresholdReached) {
        saveButton.isHidden = false
        statusLabel.text = "Minimum map size reached. You can save anytime now"
      }
      else {
        statusLabel.text = "Minimum map size reached, but you cannot save yet. Point at an area wth many feature points and scan it until the save button appears."
        }
    }
    
    
    if (LibPlacenote.instance.getMappingQuality() == LibPlacenote.MappingQuality.good) {
      mapQualityThresholdReached = true
    }
 
    
  }
  
  func onStatusChange(_ prevStatus: LibPlacenote.MappingStatus, _ currStatus: LibPlacenote.MappingStatus) {
    
  }
  
  func onLocalized() {
    
    // placenote sends 1 localized callback when it localizes.
    // Use this to load content
    statusLabel.text = "Relocalized Scene!"
    let objPos = UserDefaults.standard.object(forKey: "objPosition") as? [Float] ?? [Float]()
    let objPosition: SCNVector3 = SCNVector3(x: objPos[0], y: objPos[1], z: objPos[2])
    
    placeObject(pos: objPosition)
    
    // go to the loading panel from where you can exit
    loadingButtonPanel.isHidden = false
  }
  
  @IBAction func exitSession(_ sender: Any) {
    
    loadingButtonPanel.isHidden = true
    initPanel.isHidden = false
    
    LibPlacenote.instance.stopSession()
    ptViz?.clearPointCloud()
    
    // find the sphere in the scene and delete it
    self.sceneView.scene.rootNode.childNode(withName: "placedSphere", recursively: true)?.removeFromParentNode()
    
    statusLabel.text = "Session was reset. Start a new map or load a map"
    
  }
  
  
  // MARK: - ARSCNViewDelegatea
  
  func session(_ session: ARSession, didFailWithError error: Error) {
    // Present an error message to the user
    
  }
  
  func sessionWasInterrupted(_ session: ARSession) {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
  }
  
  func sessionInterruptionEnded(_ session: ARSession) {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
  }
}

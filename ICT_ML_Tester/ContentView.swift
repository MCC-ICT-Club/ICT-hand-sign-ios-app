//
//  ContentView.swift
//  ICT_ML_Tester
//
//  Created by Rylan Meilutis on 9/26/24.
//

import UIKit
import AVFoundation
import Photos

import SwiftUI
import UIKit

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var mode: Mode
    @Binding var selectedClass: String?

    // This method creates and returns an instance of your ViewController
    func makeUIViewController(context: Context) -> ViewController {
        let viewController = ViewController()
        viewController.isVideoMode = mode == .video
        viewController.isCameraRollMode = mode == .cameraRoll
        viewController.isCaptureMode = mode == .CaptureMode
        viewController.selectedClass = selectedClass
        return viewController
    }

    // This method updates the UIViewController as needed
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        uiViewController.isVideoMode = mode == .video
        uiViewController.isCameraRollMode = mode == .cameraRoll
        uiViewController.isCaptureMode = mode == .CaptureMode
        uiViewController.selectedClass = selectedClass
        uiViewController.updateCaptureButton() // Update button whenever the mode changes
    }
}

enum Mode: String, CaseIterable {
    case photo = "Photo Mode"
    case video = "Video Mode"
    case cameraRoll = "Camera Roll Mode"
    case CaptureMode = "Capture Mode"
}

struct ContentView: View {
    @State private var isShowingSettings = false
    @State private var selectedMode: Mode = .photo
    @State private var classes: [String] = []
    @State private var selectedClass: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            CameraViewControllerRepresentable(mode: $selectedMode, selectedClass: $selectedClass)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        isShowingSettings.toggle()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
            // If in CaptureMode, overlay the picker
            if selectedMode == .CaptureMode {
                VStack {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    } else {
                         Picker("Select Class", selection: $selectedClass) {
                            ForEach(classes, id: \.self) { className in
                                Text(className)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .labelsHidden()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .position(x: UIScreen.main.bounds.width / 2 - 10, y: UIScreen.main.bounds.height - 220)
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(selectedMode: $selectedMode)
        }
        .onChange(of: selectedMode) {
            if selectedMode == .CaptureMode {
                    fetchClasses()
                }
        }
    }

    func fetchClasses() {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        guard let url = URL(string: serverURL + "/classes") else {
            self.errorMessage = "Invalid server URL."
            return
        }

        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error fetching classes: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received."
                }
                return
            }

            do {
                let classes = try JSONDecoder().decode([String].self, from: data)
                DispatchQueue.main.async {
                    self.classes = classes
                    if !classes.isEmpty {
                        self.selectedClass = classes[0]
                    }
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error parsing classes: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

struct SettingsView: View {
    @Binding var selectedMode: Mode
    @Environment(\.presentationMode) var presentationMode // To control dismissing the sheet
    @State private var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "http://default-server-url.com" // Default server URL

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(selection: $selectedMode, label: Text("Select Mode")) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())  // Dial picker style
                }
                
                Section(header: Text("Server URL")) {
                    TextField("Enter Server URL", text: $serverURL)
                        .keyboardType(.URL)  // Proper keyboard type for URL input
                        .autocapitalization(.none)  // No capitalization for URL
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .toolbar { // Add toolbar with the Done button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Save the server URL and other settings to UserDefaults
                        UserDefaults.standard.set(serverURL, forKey: "serverURL")
                        UserDefaults.standard.set(selectedMode.rawValue, forKey: "selectedMode")

                        // Dismiss the sheet
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Load any persisted settings or set default server URL if none exists
            if UserDefaults.standard.string(forKey: "serverURL") == nil {
                UserDefaults.standard.set("http://default-server-url.com", forKey: "serverURL")
            }
            serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        }
    }
}

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    var captureButton: UIButton!
    var resultLabel: UILabel!
    var imageView: UIImageView! // Image view to display captured image or selected image
    var previewLayer: AVCaptureVideoPreviewLayer! // The camera preview layer
    var flipCameraButton: UIButton! // Camera flip button
    var tapToDismissOverlayView: UIView! // A transparent view to detect tap to dismiss the image

    var captureSession: AVCaptureSession!
    var photoOutput: AVCapturePhotoOutput!
    var videoOutput: AVCaptureVideoDataOutput!

    var lastPrediction: String = "capture a frame to continue"
    var isVideoMode: Bool = false
    var isCameraRollMode: Bool = false
    var isCaptureMode: Bool = false
    var isAwaitingServerResponse: Bool = false
    var isUsingFrontCamera: Bool = false // Track whether the front or rear camera is active
    var selectedClass: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true

        let value = UIInterfaceOrientation.landscapeLeft.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")

        setupCaptureSession()
        setupUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Re-enable the idle timer when the view is dismissed
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        setupCameraInput(isFront: isUsingFrontCamera) // Initially start with rear camera

        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Initialize the camera preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0) // Ensure the preview is behind other UI elements

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }

    func setupUI() {
        // Image view to display captured photo or camera roll image
        imageView = UIImageView(frame: view.bounds)
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true // Initially hidden, shown after photo is taken
        view.addSubview(imageView)

        // Transparent overlay to detect taps for dismissing image
        tapToDismissOverlayView = UIView(frame: view.bounds)
        tapToDismissOverlayView.backgroundColor = UIColor.clear
        tapToDismissOverlayView.isHidden = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissImageView))
        tapToDismissOverlayView.addGestureRecognizer(tapGesture)
        view.addSubview(tapToDismissOverlayView)

        // Capture Button (changes based on the mode)
        captureButton = UIButton(type: .system)
        captureButton.frame = CGRect(x: 20, y: 95, width: 150, height: 30)
        captureButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.layer.cornerRadius = 10
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        // Camera Flip Button
        flipCameraButton = UIButton(type: .system)
        flipCameraButton.frame = CGRect(x: 20, y: 60, width: 150, height: 30)
        flipCameraButton.setTitle("Flip Camera", for: .normal)
        flipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        flipCameraButton.setTitleColor(.white, for: .normal)
        flipCameraButton.layer.cornerRadius = 10
        flipCameraButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipCameraButton)

        // Result Label
        resultLabel = UILabel()
        resultLabel.text = "Prediction: \(lastPrediction)"
        resultLabel.textColor = .white
        resultLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        resultLabel.frame = CGRect(x: 20, y: view.frame.height - 80, width: view.frame.width - 40, height: 50)
        resultLabel.textAlignment = .center
        resultLabel.layer.cornerRadius = 10
        resultLabel.layer.masksToBounds = true
        resultLabel.isHidden = true // Initially hidden
        view.addSubview(resultLabel)
    }

    @objc func dismissImageView() {
        // Set the image view to a black image or clear it
        imageView.image = UIImage.blackImage(of: imageView.frame.size) // Set to a black image

        // Hide the image and result label
        imageView.isHidden = true
        resultLabel.isHidden = true
        tapToDismissOverlayView.isHidden = true

        // Only resume the camera preview if not in Camera Roll Mode
        if !isCameraRollMode {
            showCameraPreview()
        }
    }

    @objc func flipCamera() {
        isUsingFrontCamera.toggle() // Toggle between front and rear cameras
        captureSession.stopRunning() // Stop the session before reconfiguring
        setupCameraInput(isFront: isUsingFrontCamera)
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning() // Restart the session with the new input
        }
    }

    func setupCameraInput(isFront: Bool) {
        // Remove existing input
        if let currentInput = captureSession.inputs.first {
            captureSession.removeInput(currentInput)
        }

        // Configure new camera input (front or rear)
        let cameraPosition: AVCaptureDevice.Position = isFront ? .front : .back
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else { return }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        } catch {
            print("Error switching cameras: \(error)")
        }
    }

    @objc func captureTapped() {
        if isCameraRollMode {
            openPhotoPicker()
        } else {
            // Ensure the capture session is running
            DispatchQueue.global(qos: .background).async {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                } // Restart the session with the new input
            }
           

            // Capture photo in photo mode
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else { return }
        let capturedImage = UIImage(data: imageData)

        // Show the captured image and the label
        if let image = capturedImage {
            imageView.image = image
            imageView.isHidden = false
            resultLabel.isHidden = false
            tapToDismissOverlayView.isHidden = false

            // Hide the camera preview until the screen is tapped
            hideCameraPreview()
        }
        sendImageToServer(imageData: imageData)
    }

    func hideCameraPreview() {
        // Hide the camera preview and bring the captured image to front
        captureSession.stopRunning()
        view.bringSubviewToFront(imageView)
        view.bringSubviewToFront(resultLabel)
        view.bringSubviewToFront(tapToDismissOverlayView)
    }

    func showCameraPreview() {
        // Resume the camera preview
        DispatchQueue.main.async {
            self.imageView.isHidden = true // Ensure that the image view is hidden when preview is started
            self.view.backgroundColor = .clear // Reset background color to default for preview
            self.view.layer.insertSublayer(self.previewLayer, at: 0) // Reinsert preview layer if removed
            DispatchQueue.global(qos: .background).async {
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
            }
        }
    }

    func openPhotoPicker() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] as? UIImage {
            // Display the selected image in the imageView
            imageView.image = image
            imageView.isHidden = false
            resultLabel.isHidden = false // Hide the label until prediction
            tapToDismissOverlayView.isHidden = false
            if let imgData = image.jpegData(compressionQuality: 0.8){
                sendImageToServer(imageData: imgData)
            }
            // Ensure the camera preview is stopped
            hideCameraPreview()
        }
        dismiss(animated: true, completion: nil)
    }

    func updateCaptureButton() {
        if isVideoMode {
            dismissImageView()
            captureButton.isHidden = true // Hide button in video mode
            flipCameraButton.isHidden = false
            captureButton.frame = CGRect(x: 20, y: 95, width: 150, height: 30)
            if !captureSession.isRunning {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
            showCameraPreview() // Ensure preview is shown
        } else if isCameraRollMode {
            dismissImageView()
            captureButton.isHidden = false
            flipCameraButton.isHidden = true
            captureButton.frame = CGRect(x: 20, y: 60, width: 150, height: 30)
            captureButton.setTitleColor(.white, for: .normal)

            captureButton.setTitle("Select Photo", for: .normal) // Show "Select Photo" in camera roll mode
            showCameraRollImage() // Show the image and black background in Camera Roll Mode
        } else if isCaptureMode {
            dismissImageView()
            captureButton.isHidden = false
            flipCameraButton.isHidden = false
            captureButton.frame = CGRect(x: 20, y: 95, width: 150, height: 30)
            captureButton.setTitle("Capture", for: .normal)
            if !captureSession.isRunning {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
            showCameraPreview()
        } else {
            dismissImageView()
            captureButton.frame = CGRect(x: 20, y: 95, width: 150, height: 30)
            resultLabel.isHidden = true

            captureButton.isHidden = false
            flipCameraButton.isHidden = false

            captureButton.setTitle("Capture", for: .normal) // Default to "Capture" in photo mode
            if !captureSession.isRunning {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
            showCameraPreview() // Show the camera preview in Photo Mode
        }
    }

    func showCameraRollImage() {
        // Stop the camera preview
        DispatchQueue.main.async {
            self.captureSession.stopRunning()

            // Set the background to black
            self.view.backgroundColor = .black

            // Remove the preview layer from the view if it's there
            if let previewLayer = self.previewLayer {
                previewLayer.removeFromSuperlayer()
            }

            // Show the selected image
            self.imageView.isHidden = false
            self.view.bringSubviewToFront(self.imageView)
            self.view.bringSubviewToFront(self.resultLabel)
            self.view.bringSubviewToFront(self.captureButton)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isVideoMode && !isAwaitingServerResponse {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()

            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let imageData = uiImage.jpegData(compressionQuality: 0.8) {
                    isAwaitingServerResponse = true
                    sendImageToServer(imageData: imageData)
                }
            }
        }
    }

    func sendImageToServer(imageData: Data) {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        let endpoint = isCaptureMode ? "/upload" : "/predict"
        guard let url = URL(string: serverURL + endpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        if isCaptureMode {
            // Add class_name
            guard let selectedClass = selectedClass else {
                DispatchQueue.main.async {
                    self.resultLabel.text = "No class selected."
                    self.resultLabel.isHidden = false
                }
                return
            }

        // Add class_name as a form field
           
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"class_name\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(selectedClass)\r\n".data(using: .utf8)!)
            

//            body.append("--\(boundary)--\r\n".data(using: .utf8)!)


        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        print(body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.resultLabel.text = "Error uploading image: \(error?.localizedDescription ?? "Unknown error")"
                    self.resultLabel.isHidden = false
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if self.isCaptureMode {
                        DispatchQueue.main.async {
                            self.resultLabel.text = "Image uploaded successfully."
                            self.resultLabel.isHidden = false
                        }
                        self.isAwaitingServerResponse = false
                    } else {
                        do {
                            let result = try JSONDecoder().decode(PredictionResponse.self, from: data)
                            let lastPredictedClass = result.predicted_class

                            DispatchQueue.main.async {
                                self.resultLabel.text = "Predicted Class: \(lastPredictedClass)"
                                self.resultLabel.isHidden = false // Make sure the label is shown
                            }
                            self.isAwaitingServerResponse = false
                        } catch {
                            DispatchQueue.main.async {
                                self.resultLabel.text = "Error decoding response."
                                self.resultLabel.isHidden = false
                            }
                            self.isAwaitingServerResponse = false
                        }
                    }
                } else {
                    // Handle non-200 response
                    DispatchQueue.main.async {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error."
                        self.resultLabel.text = "Server error: \(errorMsg)"
                        print("Server error: \(errorMsg)")
                        self.resultLabel.isHidden = false
                    }
                    self.isAwaitingServerResponse = false
                }
            } else {
                DispatchQueue.main.async {
                    self.resultLabel.text = "Invalid server response."
                    self.resultLabel.isHidden = false
                }
                self.isAwaitingServerResponse = false
            }
        }

        task.resume()
    }

    struct PredictionResponse: Codable {
        let predicted_class: String
    }
}

extension UIImage {
    static func blackImage(of size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let blackImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return blackImage
    }
}

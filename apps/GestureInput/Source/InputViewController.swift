import CoreML
import UIKit

import RxCocoa
import RxSwift
import SnapKit

fileprivate var touchesLabelFrequencies: [Touches_Label: Double] = [
    .checkmark: 1,
    .xmark: 1,
    .lineAscending: 1,
    .scribble: 1,
    .circle: 1,
    .semicircleOpenUp: 1,
    .heart: 1,
    .plusSign: 1,
    .questionMark: 1,
    .letterACapital: 1,
    .letterBCapital: 1,
    .faceHappy: 1,
    .faceSad: 1
]

/**
 * Produces Touches_Labels with frequencies proportional to the values in
 * touchesLabelFrequencies.
 */
fileprivate func randomTouchesLabel() -> Touches_Label {
    let sumFrequencies = touchesLabelFrequencies.values.reduce(0, +)
    var random = (Double(arc4random()) / Double(UINT32_MAX)) * sumFrequencies
    
    for (label, frequency) in touchesLabelFrequencies {
        if random < frequency {
            return label
        }
        
        random -= frequency
    }
    
    // Will never be reached.
    return Touches_Label.other
}

class InputViewController: UIViewController {
    var disposeBag = DisposeBag()
    
    enum State {
        case drawing
        case reviewing
    }
    
    private(set) var state = Variable<State>(.drawing)
    
    private var targetClass = Variable<Touches_Label?>(nil)
    private var targetClassName: Observable<String?> {
        return targetClass
            .asObservable()
            .map { $0?.name }
    }
    
    private var canvas: CanvasView!
    
    private var reviewImageView: UIImageView!
    
    init() {
        super.init(nibName: nil, bundle: nil)
        
        title = "Add New Data"
        
        navigationItem.backBarButtonItem = UIBarButtonItem(title: nil, style: .plain, target: self, action: #selector(closeMe))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func closeMe() {
        navigationController?.popViewController(animated: true)
    }
    
    private func stateDidChange(newState state: State) {
        switch state {
        case .drawing:
            canvas.clear()
            targetClass.value = randomTouchesLabel()
        case .reviewing:
            reviewImageView.image = canvas.currentDrawing.rasterized()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.white
        
        let isDrawing = state
            .asObservable()
            .map { $0 == .drawing }
        
        canvas = CanvasView()
        view.addSubview(canvas)
        
        canvas.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.size.equalToSuperview()
        }
        
        isDrawing
            .map { !$0 }
            .bind(to: canvas.rx.isHidden)
            .disposed(by: disposeBag)
        
        let isReviewing = state
            .asObservable()
            .map { $0 == .reviewing }
        
        reviewImageView = UIImageView()
        reviewImageView.contentMode = .scaleAspectFit
        view.addSubview(reviewImageView)
        
        reviewImageView.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.size.equalToSuperview()
        }
        
        isReviewing
            .map { !$0 }
            .bind(to: reviewImageView.rx.isHidden)
            .disposed(by: disposeBag)
        
        state
            .asObservable()
            .subscribe(onNext: { [weak self] state in
                self?.stateDidChange(newState: state)
            })
            .disposed(by: disposeBag)
        
        let targetClassLabel = UILabel()
        targetClassLabel.textColor = UIColor.black
        view.addSubview(targetClassLabel)
        
        targetClassLabel.snp.makeConstraints { (make) in
            make.centerX.equalToSuperview()
            make.top.equalTo(topLayoutGuide.snp.bottom).offset(10)
        }
        
        Observable.combineLatest(isDrawing, targetClassName) { (isDrawing, targetClassName) -> String in
                return (isDrawing ? "Draw: " : "You drew: ") + (targetClassName ?? "")
            }
            .bind(to: targetClassLabel.rx.text)
            .disposed(by: disposeBag)
        
        let discardButton = makeSimpleButton()
        discardButton.setTitle("Discard", for: .normal)
        view.addSubview(discardButton)
        
        discardButton.snp.makeConstraints { (make) in
            make.left.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(20)
        }
        
        discardButton.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self] in
                guard let me = self else {
                    return
                }
                
                if me.state.value == .drawing {
                    me.canvas.clear()
                } else {
                    me.state.value = .drawing
                }
            })
            .disposed(by: disposeBag)
        
        let nextButton = makeSimpleButton()
        nextButton.setTitle("Next", for: .normal)
        view.addSubview(nextButton)
        
        nextButton.snp.makeConstraints { (make) in
            make.right.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(20)
        }
        
        nextButton.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self] in
                guard let me = self else {
                    return
                }
                
                if me.state.value == .drawing {
                    me.state.value = .reviewing
                } else {
                    if let targetClass = me.targetClass.value {
                        DataCache.shared.drawings.append(me.canvas.currentDrawing)
                        DataCache.shared.labels.append(targetClass)
                    }

                    me.state.value = .drawing
                }
            })
            .disposed(by: disposeBag)
        
        let saveButton = makeSimpleButton()
        saveButton.setTitle("Save Cache", for: .normal)
        view.addSubview(saveButton)
        
        saveButton.snp.makeConstraints { (make) in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(20)
        }
        
        saveButton.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: {
                let _ = DataCache.shared.save()
            })
            .disposed(by: disposeBag)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let _ = DataCache.shared.load()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        let _ = DataCache.shared.save()
    }
}

class CanvasView: UIView {
    private(set) var disposeBag = DisposeBag()
    
    private var imageView: UIImageView!
    
    private var currentTouch: UITouch?
    private var lastPosition: CGPoint?
//    private var activeTouches = Set<UITouch>()
    
    private(set) var currentDrawing = Drawing()
    private var currentStroke = Stroke()
    
    init() {
        super.init(frame: CGRect.zero)
        
        isAccessibilityElement = true
        accessibilityLabel = "Drawing canvas"
        accessibilityTraits |= UIAccessibilityTraitAllowsDirectInteraction
        
        isMultipleTouchEnabled = true
        
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        
        imageView.snp.makeConstraints { (make) in
            make.size.equalToSuperview()
            make.center.equalToSuperview()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func clear() {
        imageView.image = nil
        currentDrawing = Drawing()
        currentStroke = Stroke()
        
        resetTouch()
    }
    
    private func updatePreview(touchPosition point: CGPoint) {
        let lastPositionOpt = self.lastPosition
        self.lastPosition = point
        
        let size = bounds.size
        
        UIGraphicsBeginImageContext(size)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return
        }
        
        if let image = imageView.image {
            image.draw(at: .zero)
        }
        
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        if let lastPosition = lastPositionOpt {
            context.move(to: lastPosition)
            context.addLine(to: point)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(8)
            context.strokePath()
        }
        
        imageView.image = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
    }
    
    private func updateTouch() {
        guard let touch = currentTouch else {
            return
        }
        
        let position = touch.location(in: self)
    
        updatePreview(touchPosition: position)
        
        let sample = TouchSample(
            time: touch.timestamp,
            position: position,
            majorRadius: Double(touch.majorRadius)
        )
        
        currentStroke.samples.append(sample)
    }
    
    private func resetTouch() {
        currentTouch = nil
        lastPosition = nil
    }
    
    private func touchEnded() {
        resetTouch()
        
        currentDrawing.strokes.append(currentStroke)
        currentStroke = Stroke()
    }
    
    // MARK: UIView
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
//        activeTouches.formUnion(touches)
        
        if currentTouch == nil {
            currentTouch = touches.first!
        }
        
        updateTouch()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let currentTouch = currentTouch, touches.contains(currentTouch) else {
            return
        }
        
        updateTouch()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
//        activeTouches.subtract(touches)
        
        guard let currentTouch = currentTouch, touches.contains(currentTouch) else {
            return
        }
        
        updateTouch()
        touchEnded()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
//        activeTouches.subtract(touches)
        
        guard let currentTouch = currentTouch, touches.contains(currentTouch) else {
            return
        }
        
        updateTouch()
        touchEnded()
    }
}

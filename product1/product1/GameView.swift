import SwiftUI
import AVFoundation
import CoreGraphics
import Combine

struct QA: Identifiable {
    let id = UUID()
    let left: String
    let right: String
    let answer: String
    let options: [String]
    let image: String
    let movieName: String
    
    let leftRuby: [RubyWord]?
    let rightRuby: [RubyWord]?
    
    var correctSentence: String {
        return left + answer + right
    }
    static func == (lhs: QA, rhs: QA) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GameView: View {
    // ドラッグ判定用
    enum Target: Int, CaseIterable { case left, center, right }
    private let minDragDistance: CGFloat = 20
    private let slopeThreshold: CGFloat = 0.5
    @State private var inputEnabled = true
    
    @State private var questions: [QA]
    @State private var optionsShuffled: [String]
    @State private var currentIndex = 0
    
    // ドラッグ中のホバーと確定
    @GestureState private var hoverTarget: Target? = nil
    @State private var currentTarget: Target? = nil
    @State private var showAim = false
    
    @State private var confirmedAnswer: String? = nil
    @State private var showResult = false
    @State private var isCorrect = false
    
    // タイマー
    @State private var remainingTime = 30
    private let totalTime = 30
    @State private var progress: CGFloat = 1
    @State private var timerPublisher = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timerRunning = false
    
    // オーバーレイと終了
    @State private var showOverlay = false   // ← 初期値 false に変更
    @State private var isFinished = false
    
    @Binding var path: NavigationPath
    @State private var showVideo = false
    @State private var player: AVPlayer? = nil
    
    // 答えの表示
    @State private var correctAnswersCount = 0
    @State private var inCorrectAnswersCount = 0
    
    // ゲーム開始時刻／所要時間
    @State private var gameStartTime: Date? = nil
    @State private var overallTimeTaken: TimeInterval? = nil
    
    // 効果音
    @State private var soundPlayer: AVAudioPlayer?
    @EnvironmentObject var bgmManager: BGMManager
    
    // 操作ヒント
    @State private var showDragHint = true
    @State private var animateHint = false
    @State private var showHintButton: Bool = false
    
    // 解説＆正解(動画なし)の手動遷移
    @State private var showExplanation = false
    @State private var showCorrectNext = false
    
    // ルビ上のポップオーバー
    @State private var activeHintIndex: Int? = nil
    @State private var popoverText: String = ""
    
    //  ゲームチュートリアルの判定
    @AppStorage("hasSeenGameTutorial") private var hasSeenGameTutorial = false
    
    @State private var isShowingTutorial = false
    
    init(questions: [QA], path: Binding<NavigationPath>) {
        _questions = State(initialValue: questions.shuffled())
        _optionsShuffled = State(initialValue: questions.first?.options ?? [])
        _path = path
    }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                if !questions.isEmpty {
                    Image(questions[currentIndex].image)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.5)
                        .ignoresSafeArea()
                } else {
                    Color.gray.opacity(0.5).ignoresSafeArea()
                }
                
                // 戻るボタン
                VStack {
                    HStack {
                        Button(action: {
                            path.removeLast()
                            SEPlayer.play(name: "backSE")
                            bgmManager.start(fileName: "mapBGM", volume: 0.1, loop: true)
                        }) {
                            Image("new_btn_back")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                        }
                        .padding(.leading, 10)
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    Spacer()
                }
                .ignoresSafeArea(.all, edges: .top)
                
                if isFinished {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    ResultView(
                        totalQuestions: questions.count,
                        correctAnswers: correctAnswersCount,
                        incorrectAnswers: inCorrectAnswersCount,
                        timeTaken: overallTimeTaken,
                        path: $path,
                        restartQuestions: questions,
                        onRetry: {
                            currentIndex = 0
                            optionsShuffled = questions.first?.options ?? []
                            correctAnswersCount = 0
                            inCorrectAnswersCount = 0
                            remainingTime = totalTime
                            progress = 1
                            isFinished = false
                            confirmedAnswer = nil
                            currentTarget = nil
                            showOverlayForQuestion()
                            bgmManager.start(fileName: "bgm_game", volume: 0.4, loop: true)
                        }
                    )
                } else if questions.isEmpty {
                    VStack {
                        Text("問題がありません。")
                            .font(.system(size: w * 0.08, weight: .bold))
                            .foregroundColor(.white)
                            .padding()
                        Button("閉じる") {
                            path.removeLast()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .onAppear { timerRunning = false }
                } else {
                    // 問題表示領域
                    VStack(spacing: h * 0.06) {
                        Spacer()
                        
                        // 問題文,タイマー
                        HStack(spacing: w * 0.02) {
                            let q = questions[currentIndex]
                            let leftWords  = q.leftRuby  ?? [RubyWord(text: q.left,  ruby: "")]
                            let rightWords = q.rightRuby ?? [RubyWord(text: q.right, ruby: "")]
                            
                            let blankText = confirmedAnswer
                            ?? hoverTarget.map { optionsShuffled[$0.rawValue] }
                            ?? currentTarget.map { optionsShuffled[$0.rawValue] }
                            ?? "？"
                            
                            let blankWord = RubyWord(text: blankText, ruby: " ")
                            let sentence = leftWords + [blankWord] + rightWords
                            
                            HStack(spacing: 1) {
                                ForEach(sentence.indices, id: \.self) { i in
                                    let w = sentence[i]
                                    let isBlank = (i == leftWords.count)
                                    
                                    GameRubyline(text: w.text, ruby: w.ruby, hasHint: w.hint != nil && !w.hint!.isEmpty)
                                        .foregroundColor(isBlank ? .red : .primary)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            guard let hint = w.hint, !hint.isEmpty else { return }
                                            popoverText = hint
                                            activeHintIndex = i
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if let hint = w.hint, !hint.isEmpty,
                                               (i == sentence.indices.last || sentence[i+1].hint != hint) {
                                                Image(systemName: "questionmark.circle.fill")
                                                    .offset(y: 2)
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.trailing, -6)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                        .onTapGesture {
                                            guard let hint = w.hint, !hint.isEmpty else { return }
                                            popoverText = hint
                                            activeHintIndex = i
                                        }
                                        .popover(
                                            isPresented: Binding(
                                                get: { activeHintIndex == i },
                                                set: { if !$0 { activeHintIndex = nil } }
                                            ),
                                            attachmentAnchor: .point(.top),
                                            arrowEdge: .bottom
                                        ) {
                                            TapoverView(text: $popoverText)
                                                .presentationCompactAdaptation(.popover)
                                        }
                                }
                            }
                            .padding(.top,5)
                            
                            // 右側タイマー表示
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: w * 0.10, height: w * 0.10)
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                                    .frame(width: w * 0.10, height: w * 0.10)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .rotation(Angle(degrees: -90))
                                    .stroke(
                                        remainingTime <= 10 ? Color.red : Color.blue,
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                    )
                                    .frame(width: w * 0.10, height: w * 0.10)
                                Text("\(remainingTime)")
                                    .font(.system(size: w * 0.035, weight: .bold))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .opacity(0.9)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.top,50)
                        .opacity(showOverlay ? 0 : 1)
                        
                        // 選択肢
                        HStack(spacing: w * 0.15) {
                            ForEach(Target.allCases, id: \.self) { t in
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(
                                            width:  (hoverTarget ?? currentTarget) == t ? w * 0.12 : w * 0.11,
                                            height: (hoverTarget ?? currentTarget) == t ? w * 0.12 : w * 0.11
                                        )
                                        .overlay(
                                            Circle()
                                                .fill(
                                                    (hoverTarget ?? currentTarget) == t
                                                    ? Color(red: 1.0, green: 0.98, blue: 0.8, opacity: 0.85)
                                                    : Color.white
                                                )
                                                .stroke(
                                                    (hoverTarget ?? currentTarget) == t
                                                    ? Color(red: 1.0, green: 0.67, blue: 0.73)
                                                    : Color.gray.opacity(0.4),
                                                    lineWidth: 6
                                                )
                                        )
                                    Text(optionsShuffled[t.rawValue])
                                        .font(.system(size: (hoverTarget ?? currentTarget) == t ? w * 0.06 : w * 0.04).bold())
                                        .foregroundColor(
                                            (hoverTarget ?? currentTarget) == t
                                            ? Color.pink.opacity(0.9)
                                            : .black
                                        )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(showOverlay ? 0 : 1)
                        
                        // 矢（エイム）の表示
                        if showAim {
                            Image("gameArrow")
                                .frame(width:50,height: 10)
                                .rotationEffect(
                                    .degrees({
                                        switch hoverTarget ?? currentTarget {
                                        case .left:        return -50
                                        case .right:       return 50
                                        case .center, nil: return 0
                                        }
                                    }())
                                )
                                .offset({
                                    switch hoverTarget ?? currentTarget {
                                    case .left:  return CGSize(width: -200, height: 0)
                                    case .right: return CGSize(width: 200, height: 0)
                                    case .center, nil: return CGSize(width: 0, height: 0)
                                    }
                                }())
                                .onChange(of: hoverTarget) { oldValue, newValue in
                                    if newValue != nil {
                                        SEPlayer.play(name: "AimSE")
                                    }
                                }
                                .animation(.easeOut(duration: 0.2), value: hoverTarget ?? currentTarget)
                        } else {
                            Spacer().frame(height: 10)
                        }
                        
                        ZStack {
                            Image(arrowImageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .scaleEffect(2.3, anchor: .center)
                                .padding(15)
                                .overlay {
                                    if showDragHint && !showOverlay && confirmedAnswer == nil {
                                        ZStack {
                                            VStack(spacing: 8) {
                                                Image("image_下矢印")
                                                    .resizable()
                                                    .frame(width: 100, height: 110)
                                                    .opacity(animateHint ? 0.5 : 1.0)
                                                    .offset(y: animateHint ? 50 : 45)
                                                    .animation(
                                                        showDragHint
                                                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                                        : .default,
                                                        value: animateHint
                                                    )
                                            }
                                            HintHandView()
                                                .allowsHitTesting(false) // タップを無効化
                                        }
                                        .transition(.opacity)
                                        .onAppear { animateHint = true }
                                    }
                                }
                        }
                        .allowsHitTesting(
                            inputEnabled
                            && !showOverlay
                            && !showVideo
                            && !showResult
                            && !showExplanation
                            && !showCorrectNext
                            && !isShowingTutorial
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    guard inputEnabled else { return }
                                    if v.translation.height > 4 {
                                        if showDragHint {
                                            showDragHint = false
                                            animateHint = false
                                            showAim = true
                                            SEPlayer.play(name: "AimSE")
                                        }
                                    }
                                }
                                .updating($hoverTarget) { v, state, _ in
                                    guard inputEnabled else { return }
                                    let d = CGVector(dx: v.translation.width, dy: v.translation.height)
                                    guard d.dy > minDragDistance else { return }
                                    let r = d.dx / d.dy
                                    state = r < -slopeThreshold ? .right
                                    : r >  slopeThreshold ? .left
                                    : .center
                                }
                                .onEnded { v in
                                    guard inputEnabled else { return }
                                    let d = CGVector(dx: v.translation.width, dy: v.translation.height)
                                    guard d.dy > minDragDistance else { return }
                                    let r = d.dx / d.dy
                                    let final: Target = r < -slopeThreshold ? .right
                                    : r >  slopeThreshold ? .left
                                    : .center
                                    currentTarget   = final
                                    confirmedAnswer = optionsShuffled[final.rawValue]
                                    isCorrect       = (confirmedAnswer == questions[currentIndex].answer)
                                    showResult = true
                                    inputEnabled = false
                                    stopTimer()
                                    
                                    if isCorrect {
                                        correctAnswersCount += 1
                                        playFeedbackSound(isCorrect: true)
                                    } else {
                                        inCorrectAnswersCount += 1
                                        playFeedbackSound(isCorrect: false)
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        showResult = false
                                        if isCorrect {
                                            if !questions[currentIndex].movieName.isEmpty {
                                                playVideo()
                                            } else {
                                                showCorrectNext = true
                                            }
                                        } else {
                                            showExplanation = true
                                        }
                                    }
                                }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, h * 0.1)
                        .opacity(showOverlay ? 0 : 1)
                        
                        Spacer()
                    }
                    .opacity(isShowingTutorial ? 0 : 1)
                    .id(currentIndex)
                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                            removal:    .move(edge: .leading)))
                    .animation(.easeOut(duration: 0.2), value: currentIndex)
                    
                    if showResult {
                        Text(isCorrect ? "⭕️" : "❌")
                            .font(.system(size: w * 0.2))
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    // 動画表示
                    if showVideo, let player = player {
                        Color.black.opacity(0.7).ignoresSafeArea()
                        
                        VStack {
                            GameRubyLine(tokens: sentenceTokens(for: questions[currentIndex],
                                                                fill: questions[currentIndex].answer))
                            .padding()
                            .frame(height: 100)
                            .background(Color.white)
                            .cornerRadius(12)
                            
                            
                            PlayerView(player: player)
                                .frame(width: w * 0.8, height: w * 0.4)
                                .padding()
                            // .background(Color.black)
                                .cornerRadius(12)
                                .onAppear {
                                    player.seek(to: .zero)
                                    player.play()
                                }
                            
                            HStack {
                                Button {
                                    SEPlayer.play(name: "backSE")
                                    replayVideo()
                                } label: {
                                    Image("もう一度みる")
                                        .resizable()
                                        .frame(width: 200, height: 100)
                                        .padding()
                                }
                                
                                Button {
                                    SEPlayer.play(name: "nextSE")
                                    self.player?.pause()
                                    self.player = nil
                                    self.showVideo = false
                                    self.nextQuestion()
                                    self.bgmManager.resume()
                                } label: {
                                    Image("つぎへ")
                                        .resizable()
                                        .frame(width: 200, height: 100)
                                        .padding()
                                }
                            }
                        }
                        .padding()
                    }
                    
                    // 第何問オーバーレイ
                    if showOverlay {
                        Color.black.opacity(0.7).ignoresSafeArea()
                        
                        let current = currentIndex + 1
                        let total = questions.count
                        
                        VStack(spacing: 24) {
                            
                            Text("\(current)/\(total)")
                                .font(.system(size: w * 0.08, weight: .heavy))
                                .foregroundColor(.white)
                            ZStack(alignment: .leading) {
                                let fullWidth = w * 0.6
                                let ratio = CGFloat(current) / CGFloat(max(total, 1))
                                
                                
                                Capsule()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: fullWidth, height: 20)
                                
                                let gradient = LinearGradient(
                                    colors: [
                                        Color(red: 0.78, green: 1.00, blue: 0.78)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                
                                gradient
                                    .frame(width: fullWidth, height: 20)
                                    .mask(
                                        Capsule()
                                            .frame(width: fullWidth * ratio, height: 20, alignment: .leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    )
                                    .animation(.easeOut(duration: 0.35), value: current)
                                
                            }
                            
                        }
                    }
                    
                    
                    // 解説オーバーレイ
                    if showExplanation {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .onTapGesture { }
                        
                        VStack {
                            GameExplanationView(
                                particleName: questions[currentIndex].answer,
                                correctSentence: questions[currentIndex].correctSentence,
                                leftRuby:  questions[currentIndex].leftRuby  ?? [RubyWord(text: questions[currentIndex].left,  ruby: "")],
                                rightRuby: questions[currentIndex].rightRuby ?? [RubyWord(text: questions[currentIndex].right, ruby: "")]
                            )
                            .frame(maxWidth: 900)
                            .shadow(radius: 20)
                            //.background(Color.black)
                            .cornerRadius(12)
                            .transition(.scale.combined(with: .opacity))
                            
                            Button {
                                SEPlayer.play(name: "nextSE")
                                showExplanation = false
                                nextQuestion()
                                bgmManager.resume()
                            } label: {
                                Image("つぎへ")
                                    .resizable()
                                    .frame(width: 200, height: 100)
                            }
                            .padding(.bottom, 20)
                        }
                        .padding()
                        .animation(.easeOut(duration: 0.2), value: showExplanation)
                    }
                    
                    
                    if showCorrectNext {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("正解！")
                                .font(.title).bold()
                                .foregroundColor(.white)
                            Button {
                                SEPlayer.play(name: "nextSE")
                                showCorrectNext = false
                                nextQuestion()
                                bgmManager.resume()
                            } label: {
                                Image("つぎへ")
                                    .resizable()
                                    .frame(width: 200, height: 100)
                            }
                        }
                        .padding()
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: showCorrectNext)
                    }
                }
                if isShowingTutorial {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture {
                            hasSeenGameTutorial = true
                            isShowingTutorial = false
                            showOverlayForQuestion()
                        }
                    
                    
                    TutorialView()
                        .cornerRadius(20)
                        .frame(width: w * 0.7, height: h * 0.7)
                        .padding()
                    
                        .onTapGesture { }
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeOut(duration: 0.25), value: isShowingTutorial)
                }
            }
            
            .onReceive(timerPublisher) { _ in
                guard timerRunning else { return }
                guard !questions.isEmpty else {
                    stopTimer()
                    return
                }
                
                if remainingTime > 0 {
                    remainingTime -= 1
                    withAnimation(.linear(duration: 1)) {
                        progress = CGFloat(remainingTime) / CGFloat(totalTime)
                    }
                } else {
                    // タイムアップ
                    stopTimer()
                    inputEnabled = false
                    isCorrect  = false
                    showResult = true
                    playFeedbackSound(isCorrect: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showResult = false
                        showExplanation = true
                    }
                }
            }
            .onAppear {
                if gameStartTime == nil { gameStartTime = Date() }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    bgmManager.start(fileName: "bgm_game", volume: 0.4, loop: true)
                }
                
                guard !questions.isEmpty else {
                    isFinished = true
                    timerRunning = false
                    return
                }
                
                optionsShuffled = questions[currentIndex].options
                
                if hasSeenGameTutorial {
                    showOverlayForQuestion()
                } else {
                    isShowingTutorial = true
                    inputEnabled = false
                    timerRunning = false
                    showOverlay = false
                }
            }
            .onDisappear {
                //bgmManager.stop()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func nextQuestion() {
        showExplanation = false
        showCorrectNext = false
        timerRunning = false
        showAim = false
        guard !questions.isEmpty else {
            isFinished = true
            if let startTime = gameStartTime {
                overallTimeTaken = Date().timeIntervalSince(startTime)
            }
            return
        }
        
        if currentIndex + 1 < questions.count {
            currentIndex += 1
            optionsShuffled = questions[currentIndex].options
            showOverlayForQuestion()
        } else {
            isFinished = true
            if let startTime = gameStartTime {
                overallTimeTaken = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func showOverlayForQuestion() {
        confirmedAnswer = nil
        currentTarget   = nil
        remainingTime   = totalTime
        progress        = 1
        showOverlay     = true
        inputEnabled    = false
        activeHintIndex = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            withAnimation(.easeOut(duration: 0.5)) {
                showOverlay = false
            }
            timerRunning = true
            inputEnabled = true
            showHint()
        }
    }
    
    private var arrowImageName: String {
        switch (hoverTarget ?? currentTarget) {
        case .left:  return "yabu_left"
        case .right: return "yabu_right"
        default:     return "yabu_center"
        }
    }
    
    private func stopTimer() {
        timerRunning = false
    }
    
    private func playVideo() {
        let name = questions[currentIndex].movieName
        if isCorrect && !name.isEmpty, let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            player = AVPlayer(url: url)
            showVideo = true
            inputEnabled = false
            bgmManager.volumedown()
        } else {
            showCorrectNext = true
        }
    }
    
    private func playFeedbackSound(isCorrect: Bool) {
        let soundFileName = isCorrect ? "sound_correct" : "sound_incorrect"
        guard let url = Bundle.main.url(forResource: soundFileName, withExtension: "mp3") else {
            print("効果音ファイルが見つかりません: \(soundFileName).mp3")
            return
        }
        do {
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.play()
        } catch {
            print("効果音の再生に失敗しました: \(error.localizedDescription)")
        }
    }
    
    private func showHint() {
        showDragHint = true
        animateHint = false
        DispatchQueue.main.async { animateHint = true }
    }
    
    private func replayVideo() {
        guard let player = player else { return }
        player.seek(to: .zero)
        player.play()
    }
    
    // 完成文
    private func sentenceTokens(for q: QA, fill text: String) -> [RubyWord] {
        let left  = q.leftRuby  ?? [RubyWord(text: q.left,  ruby: "")]
        let right = q.rightRuby ?? [RubyWord(text: q.right, ruby: "")]
        let blank = RubyWord(text: text, ruby: " ")
        return left + [blank] + right
    }
}

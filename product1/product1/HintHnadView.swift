import SwiftUI

struct HintHandView: View {
    @State var animateHint = true
    @State private var offsetY: CGFloat = -50
    @State private var isVisible = true
    
    var body: some View {
        ZStack {
            if isVisible {
                Image("handGesture")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 400, height: 400)
                    .offset(x: 50,y: offsetY)
                    .animation(.easeInOut(duration: 1), value: offsetY)
                    .animation(.easeInOut(duration: 1), value: isVisible)
            }
        }
        .task {
            await startHintLoop()
        }
    }
    
    // MARK: - ループアニメーション処理
    func startHintLoop() async {
        while animateHint {
            //初期位置
            offsetY = -50
            try? await Task.sleep(nanoseconds: 100_000_000)
            //下移動
            offsetY = 100
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            // 非表示
            isVisible = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            offsetY = -50
            isVisible = true
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

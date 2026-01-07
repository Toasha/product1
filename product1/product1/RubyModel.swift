import SwiftUI

struct RubyWord: Identifiable,Hashable {
    let id = UUID()
    let text: String
    let ruby: String?
    let hint: String?
    
    init(text: String, ruby: String, hint: String? = nil) {
        self.text = text
        self.ruby = ruby
        self.hint = hint
    }
}

struct RubyInline: View {
    let text: String
    let ruby: String?
    
    var body: some View {
        VStack(alignment: .center,spacing: -1) {
            Text(ruby ?? "　")
                .font(.caption2)
                .foregroundColor(.gray)
                .opacity((ruby ?? "").isEmpty ? 0 : 1)
            Text(text)
                .bold()
                .font(.title3)
        }
    }
}

struct Rubyinline: View {
    let text: String
    let ruby: String?
    
    var body: some View {
        VStack(alignment: .center,spacing: -1) {
            Text(ruby ?? "　")
                .font(.system(size:8))
                .foregroundColor(.gray)
                .opacity((ruby ?? "").isEmpty ? 0 : 1)
            Text(text)
                .bold()
                .font(.body)
                .bold()
        }
    }
}

struct GameRubyline: View {
    let text: String
    let ruby: String?
    let hasHint: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: -2) {
            Text(ruby ?? "　")
                .font(.caption2)
                .foregroundColor(.gray)
                .opacity((ruby ?? "").isEmpty ? 0 : 1)
            
            Text(text)
                .bold()
                .font(.largeTitle)
                .underline(hasHint, color: .gray.opacity(0.5))
        }
    }
}

struct ExRubyline: View {
    let text: String
    let ruby: String?
    let hasHint: Bool
    
    var body: some View {
        VStack(alignment: .center, spacing: -2) {
            Text(ruby ?? "　")
                .font(.caption2)
                .foregroundColor(.gray)
                .opacity((ruby ?? "").isEmpty ? 0 : 1)
            
            Text(text)
                .bold()
                .font(.title3)
                .underline(hasHint, color: .gray.opacity(0.5))
        }
    }
}

struct RubyLine: View {
    let tokens: [RubyWord]
    @State private var activeGroupID: UUID? = nil
    @State private var popoverText: String = ""
    
    var body: some View {
        let groups = groupByHint(tokens)
        
        HStack(spacing: -0.5) {
            ForEach(groups) { g in
                let groupView =
                HStack(spacing: -0.5) {
                    ForEach(g.tokens) { t in
                        Rubyinline(text: t.text, ruby: t.ruby)
                    }
                }
                .font(.system(size: 18))
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if g.hint != nil {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, -2)
                            .padding(.trailing, -4)
                            .allowsHitTesting(false)
                    }
                }
                .onTapGesture {
                    guard let hint = g.hint else { return }
                    popoverText = hint
                    activeGroupID = g.id
                }
                .popover(
                    isPresented: Binding(
                        get: { activeGroupID == g.id },
                        set: { if !$0 { activeGroupID = nil } }
                    ),
                    attachmentAnchor: .point(.top),
                    arrowEdge: .bottom
                ) {
                    TapoverView(text: $popoverText)
                        .presentationCompactAdaptation(.popover)
                }
                
                groupView
            }
        }
    }
}

struct GameRubyLine: View {
    let tokens: [RubyWord]
    var body: some View {
        HStack(spacing: -0.5) {
            ForEach(tokens) { t in
                GameRubyline(text: t.text, ruby: t.ruby, hasHint: false)
            }
            .font(.system(size: 18))
        }
    }
}

struct ExRubyLine: View {
    let tokens: [RubyWord]
    var body: some View {
        HStack(spacing: -0.5) {
            ForEach(tokens) { t in
                ExRubyline(text: t.text, ruby: t.ruby, hasHint: false)
            }
            .font(.system(size: 2))
        }
    }
}

struct RubyGroup: Identifiable {
    let id = UUID()
    let tokens: [RubyWord]
    let hint: String?
    
    
}
private func groupByHint(_ tokens: [RubyWord]) -> [RubyGroup] {
    guard !tokens.isEmpty else { return [] }
    var groups: [RubyGroup] = []
    var current: [RubyWord] = []
    var currentHint: String? = tokens.first!.hint?.nilIfEmpty
    
    for t in tokens {
        let h = t.hint?.nilIfEmpty
        if h == currentHint || (current.isEmpty) {
            current.append(t)
        } else {
            groups.append(RubyGroup(tokens: current, hint: currentHint))
            current = [t]
        }
        currentHint = h
    }
    groups.append(RubyGroup(tokens: current, hint: currentHint))
    return groups
}

private extension String {
    var nilIfEmpty: String? { self.isEmpty ? nil : self }
}


struct RubyCompareLine: View {
    let tokens: [RubyWord]
    var fontSize: CGFloat = 10
    @State private var activeGroupID: UUID? = nil
    @State private var popoverText: String = ""
    
    var body: some View {
        let groups = groupByHint(tokens)
        
        FlowLayout(spacing: -0.5, lineSpacing: 2) {
            ForEach(groups) { g in
                let groupView =
                HStack(spacing: -0.5) {
                    ForEach(g.tokens) { t in
                        Rubyinline(text: t.text, ruby: t.ruby)
                            .font(.system(size: fontSize))
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if g.hint != nil {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, -2)
                            .padding(.trailing, -4)
                            .allowsHitTesting(false)
                    }
                }
                .onTapGesture {
                    guard let hint = g.hint else { return }
                    popoverText = hint
                    activeGroupID = g.id
                }
                .popover(
                    isPresented: Binding(
                        get: { activeGroupID == g.id },
                        set: { if !$0 { activeGroupID = nil } }
                    ),
                    attachmentAnchor: .point(.top),
                    arrowEdge: .bottom
                ) {
                    TapoverView(text: $popoverText)
                        .presentationCompactAdaptation(.popover)
                }
                
                groupView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates how to use `NavigationStack` with Composable Architecture applications.
  """

struct NavigationDemo: ReducerProtocol {
  struct State: Equatable {
    var path = StackState<Path.State>()
  }

  enum Action: Equatable {
    case goBackToScreen(Int)
    case goToABCButtonTapped
    case path(StackAction<Path.State, Path.Action>)
    case popToRoot
  }

  var body: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case let .goBackToScreen(n):
        state.path.removeLast(n)
        return .none

      case .goToABCButtonTapped:
        state.path.append(.screenA(.init()))
        state.path.append(.screenB(.init()))
        state.path.append(.screenC(.init()))
        return .none

      case let .path(action):
        switch action {
        case .element(id: _, action: .screenB(.screenAButtonTapped)):
          state.path.append(.screenA(.init()))
          return .none

        case .element(id: _, action: .screenB(.screenBButtonTapped)):
          state.path.append(.screenB(.init()))
          return .none

        case .element(id: _, action: .screenB(.screenCButtonTapped)):
          state.path.append(.screenC(.init()))
          return .none

        default:
          return .none
        }

      case .popToRoot:
        state.path.removeAll()
        return .none
      }
    }
    .forEach(\.path, action: /Action.path) {
      Path()
    }
  }

  struct Path: ReducerProtocol {
    enum State: Codable, Equatable, Hashable {
      case screenA(ScreenA.State)
      case screenB(ScreenB.State)
      case screenC(ScreenC.State)
    }

    enum Action: Equatable {
      case screenA(ScreenA.Action)
      case screenB(ScreenB.Action)
      case screenC(ScreenC.Action)
    }

    var body: some ReducerProtocol<State, Action> {
      Scope(state: /State.screenA, action: /Action.screenA) {
        ScreenA()
      }
      Scope(state: /State.screenB, action: /Action.screenB) {
        ScreenB()
      }
      Scope(state: /State.screenC, action: /Action.screenC) {
        ScreenC()
      }
    }
  }
}

struct NavigationDemoView: View {
  let store: StoreOf<NavigationDemo>

  var body: some View {
    ZStack(alignment: .bottom) {
      NavigationStackStore(
        self.store.scope(state: \.path, action: NavigationDemo.Action.path)
      ) {
        Form {
          Section { Text(template: readMe) }

          Section {
            NavigationLink(
              "Go to screen A",
              state: NavigationDemo.Path.State.screenA(.init())
            )
            NavigationLink(
              "Go to screen B",
              state: NavigationDemo.Path.State.screenB(.init())
            )
            NavigationLink(
              "Go to screen C",
              state: NavigationDemo.Path.State.screenC(.init())
            )
          }

          Section {
            Button("Go to A → B → C") {
              ViewStore(self.store.stateless).send(.goToABCButtonTapped)
            }
          }
        }
        .navigationTitle("Root")
      } destination: {
        switch $0 {
        case .screenA:
          CaseLet(
            state: /NavigationDemo.Path.State.screenA,
            action: NavigationDemo.Path.Action.screenA,
            then: ScreenAView.init(store:)
          )
        case .screenB:
          CaseLet(
            state: /NavigationDemo.Path.State.screenB,
            action: NavigationDemo.Path.Action.screenB,
            then: ScreenBView.init(store:)
          )
        case .screenC:
          CaseLet(
            state: /NavigationDemo.Path.State.screenC,
            action: NavigationDemo.Path.Action.screenC,
            then: ScreenCView.init(store:)
          )
        }
      }
      .zIndex(0)

      FloatingMenuView(store: self.store)
        .zIndex(1)
    }
    .navigationTitle("Navigation Stack")
  }
}

// MARK: - Floating menu

struct FloatingMenuView: View {
  let store: StoreOf<NavigationDemo>

  struct ViewState: Equatable {
    var currentStack: [String]
    var total: Int
    init(state: NavigationDemo.State) {
      self.total = 0
      self.currentStack = []
      for element in state.path {
        switch element {
        case let .screenA(screenAState):
          self.total += screenAState.count
          self.currentStack.insert("Screen A", at: 0)
        case .screenB:
          self.currentStack.insert("Screen B", at: 0)
        case let .screenC(screenBState):
          self.total += screenBState.count
          self.currentStack.insert("Screen C", at: 0)
        }
      }
    }
  }

  var body: some View {
    WithViewStore(self.store.scope(state: ViewState.init)) { viewStore in
      if viewStore.currentStack.count > 0 {
        VStack(alignment: .center) {
          Text("Total count: \(viewStore.total)")
          Button("Pop to root") {
            viewStore.send(.popToRoot, animation: .default)
          }
          Menu {
            ForEach(Array(viewStore.currentStack.enumerated()), id: \.offset) { offset, screen in
              Button("\(viewStore.currentStack.count - offset).) \(screen)") {
                viewStore.send(.goBackToScreen(offset))
              }
              .disabled(offset == 0)
            }
            Button("Root") {
              viewStore.send(.popToRoot, animation: .default)
            }
          } label: {
            Text("Current stack")
          }
        }
        .padding()
        .background(Color(.systemBackground))
        .padding(.bottom, 1)
        .transition(.opacity.animation(.default))
        .clipped()
        .shadow(color: .black.opacity(0.2), radius: 5, y: 5)
      }
    }
  }
}

// MARK: - Screen A

struct ScreenA: ReducerProtocol {
  struct State: Codable, Equatable, Hashable {
    var count = 0
    var fact: String?
    var isLoading = false
  }

  enum Action: Equatable {
    case decrementButtonTapped
    case dismissButtonTapped
    case incrementButtonTapped
    case factButtonTapped
    case factResponse(TaskResult<String>)
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.factClient) var factClient

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .decrementButtonTapped:
      state.count -= 1
      return .none

    case .dismissButtonTapped:
      return .fireAndForget {
        await self.dismiss()
      }

    case .incrementButtonTapped:
      state.count += 1
      return .none

    case .factButtonTapped:
      state.isLoading = true
      return .task { [count = state.count] in
        await .factResponse(.init { try await self.factClient.fetch(count) })
      }

    case let .factResponse(.success(fact)):
      state.isLoading = false
      state.fact = fact
      return .none

    case .factResponse(.failure):
      state.isLoading = false
      state.fact = nil
      return .none
    }
  }
}

struct ScreenAView: View {
  let store: StoreOf<ScreenA>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        Text(
          """
          This screen demonstrates a basic feature hosted in a navigation stack.

          You can also have the child feature dismiss itself, which will communicate back to the \
          root stack view to pop the feature off the stack.
          """
        )

        Section {
          HStack {
            Text("\(viewStore.count)")
            Spacer()
            Button {
              viewStore.send(.decrementButtonTapped)
            } label: {
              Image(systemName: "minus")
            }
            Button {
              viewStore.send(.incrementButtonTapped)
            } label: {
              Image(systemName: "plus")
            }
          }
          .buttonStyle(.borderless)

          Button {
            viewStore.send(.factButtonTapped)
          } label: {
            HStack {
              Text("Get fact")
              if viewStore.isLoading {
                Spacer()
                ProgressView()
              }
            }
          }

          if let fact = viewStore.fact {
            Text(fact)
          }
        }

        Section {
          Button("Dismiss") {
            viewStore.send(.dismissButtonTapped)
          }
        }

        Section {
          NavigationLink(
            "Go to screen A",
            state: NavigationDemo.Path.State.screenA(.init(count: viewStore.count))
          )
          NavigationLink(
            "Go to screen B",
            state: NavigationDemo.Path.State.screenB(.init())
          )
          NavigationLink(
            "Go to screen C",
            state: NavigationDemo.Path.State.screenC(.init(count: viewStore.count))
          )
        }
      }
    }
    .navigationTitle("Screen A")
  }
}

// MARK: - Screen B

struct ScreenB: ReducerProtocol {
  struct State: Codable, Equatable, Hashable {}

  enum Action: Equatable {
    case screenAButtonTapped
    case screenBButtonTapped
    case screenCButtonTapped
  }

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .screenAButtonTapped:
      return .none
    case .screenBButtonTapped:
      return .none
    case .screenCButtonTapped:
      return .none
    }
  }
}

struct ScreenBView: View {
  let store: StoreOf<ScreenB>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Form {
        Section {
          Text(
            """
            This screen demonstrates how to navigate to other screens without needing to compile \
            any symbols from those screens. You can send an action into the system, and allow the \
            root feature to intercept that action and push the next feature onto the stack.
            """
          )
        }
        Button("Decoupled navigation to screen A") {
          viewStore.send(.screenAButtonTapped)
        }
        Button("Decoupled navigation to screen B") {
          viewStore.send(.screenBButtonTapped)
        }
        Button("Decoupled navigation to screen C") {
          viewStore.send(.screenCButtonTapped)
        }
      }
      .navigationTitle("Screen B")
    }
  }
}

// MARK: - Screen C

struct ScreenC: ReducerProtocol {
  struct State: Codable, Equatable, Hashable {
    var count = 0
    var isTimerRunning = false
  }

  enum Action: Equatable {
    case startButtonTapped
    case stopButtonTapped
    case timerTick
  }

  @Dependency(\.mainQueue) var mainQueue
  enum CancelID { case timer }

  func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
    switch action {
    case .startButtonTapped:
      state.isTimerRunning = true
      return .run { send in
        for await _ in self.mainQueue.timer(interval: 1) {
          await send(.timerTick)
        }
      }
      .cancellable(id: CancelID.timer)
      .concatenate(with: .init(value: .stopButtonTapped))

    case .stopButtonTapped:
      state.isTimerRunning = false
      return .cancel(id: CancelID.timer)

    case .timerTick:
      state.count += 1
      return .none
    }
  }
}

struct ScreenCView: View {
  let store: StoreOf<ScreenC>

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Form {
        Text(
          """
          This screen demonstrates that if you start a long-living effects in a stack, then it \
          will automatically be torn down when the screen is dismissed.
          """
        )
        Section {
          Text("\(viewStore.count)")
          if viewStore.isTimerRunning {
            Button("Stop timer") { viewStore.send(.stopButtonTapped) }
          } else {
            Button("Start timer") { viewStore.send(.startButtonTapped) }
          }
        }

        Section {
          NavigationLink(
            "Go to screen A",
            state: NavigationDemo.Path.State.screenA(.init(count: viewStore.count))
          )
          NavigationLink(
            "Go to screen B",
            state: NavigationDemo.Path.State.screenB(.init())
          )
          NavigationLink(
            "Go to screen C",
            state: NavigationDemo.Path.State.screenC(.init())
          )
        }
      }
      .navigationTitle("Screen C")
    }
  }
}

// MARK: - Previews

struct NavigationStack_Previews: PreviewProvider {
  static var previews: some View {
    NavigationDemoView(
      store: Store(
        initialState: NavigationDemo.State(
          path: StackState([
            .screenA(ScreenA.State())
          ])
        ),
        reducer: NavigationDemo()
      )
    )
  }
}

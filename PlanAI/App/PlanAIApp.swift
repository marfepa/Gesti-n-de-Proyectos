import SwiftUI
import SwiftData

@main
struct PlanAIApp: App {
    let sharedModelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Project.self,
                ProjectTask.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo inicializar el contenedor SwiftData de PlanAI: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}

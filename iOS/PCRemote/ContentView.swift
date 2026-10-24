import SwiftUI
import GameController

private struct ControlEditRequest: Identifiable { let id: UUID }

struct TouchControl: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var key: String
    var x: Double
    var y: Double
    var size: Double = 58
    var opacity: Double = 0.62
}

@MainActor
final class ControllerState: ObservableObject {
    @Published var connected = GCController.controllers().count > 0
    private var observers: [NSObjectProtocol] = []
    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.connected = true })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.connected = !GCController.controllers().isEmpty })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

struct ContentView: View {
    @StateObject private var client = PCRemoteClient()
    @StateObject private var controller = ControllerState()
    @AppStorage("pcremote.modeGame") private var modeGame = true
    @AppStorage("pcremote.controlLayout") private var savedLayout = ""
    @State private var tab = 0
    @State private var fullScreen = false
    @State private var editing = false
    @State private var showingSettings = false
    @State private var newTitle = ""
    @State private var newKey = "SPACE"
    @State private var controls: [TouchControl] = [
        TouchControl(title: "A", key: "SPACE", x: 0.87, y: 0.69),
        TouchControl(title: "B", key: "E", x: 0.76, y: 0.53),
        TouchControl(title: "X", key: "R", x: 0.76, y: 0.82),
        TouchControl(title: "Y", key: "F", x: 0.88, y: 0.40)
    ]
    @State private var editingControl: ControlEditRequest?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if fullScreen {
                gameScreen
            } else {
                VStack(spacing: 0) {
                    header
                    Group {
                        if tab == 0 { screenTab }
                        else if tab == 1 { controlTab }
                        else { settingsTab }
                    }
                    bottomBar
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadLayout(); client.startPreview() }
        .onDisappear { client.stopPreview() }
        .sheet(isPresented: $showingSettings) { connectionSheet }
        .sheet(item: $editingControl) { request in controlEditor(id: request.id) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("PC REMOTE").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.white.opacity(0.55))
                Text(tab == 0 ? "Screen" : tab == 1 ? "Control" : "Configuración").font(.largeTitle.bold())
            }
            Spacer()
            Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3.weight(.semibold)).frame(width: 48, height: 48).glassButton() }
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)
    }

    private var screenTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Circle().fill(client.connected ? .green : .orange).frame(width: 8, height: 8)
                    Text(client.statusText).font(.footnote).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    Spacer()
                    Button("Conectar") { Task { await client.testConnection() } }.font(.footnote.weight(.semibold))
                }
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let frame = client.latestFrame {
                            Image(uiImage: frame).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity).background(Color(white: 0.06))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "display.2").font(.system(size: 42, weight: .light)).foregroundStyle(.white.opacity(0.6))
                                Text("Vista previa de la PC").font(.headline)
                                Text("Conectá el servidor de Windows para ver la pantalla real.").font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: 250)
                            }.frame(maxWidth: .infinity).frame(height: 205).background(LinearGradient(colors: [Color(white: 0.12), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { fullScreen = true } } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).padding(12).glassButton() }.padding(9)
                }.clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.13)))
                VStack(alignment: .leading, spacing: 14) {
                    Text("SCREEN SETTINGS").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.5))
                    Toggle(isOn: $modeGame.animation(.spring(response: 0.35))) {
                        Label("Modo juego", systemImage: "gamecontroller.fill")
                    }.tint(.white)
                    HStack {
                        Label("Mando conectado", systemImage: "gamecontroller")
                        Spacer()
                        Text(controller.connected ? "Detectado" : "No detectado").font(.caption).foregroundStyle(controller.connected ? .green : .white.opacity(0.5))
                    }
                    HStack {
                        Label("Controles táctiles", systemImage: "hand.tap")
                        Spacer()
                        Text(controller.connected ? "Ocultos" : modeGame ? "Activos en pantalla completa" : "Desactivados").font(.caption).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.trailing)
                    }
                    HStack(spacing: 10) {
                        Button { withAnimation { fullScreen = true } } label: { Label("Pantalla completa", systemImage: "arrow.up.left.and.arrow.down.right").frame(maxWidth: .infinity).padding(.vertical, 13).glassButton() }
                        Button { editing = true; withAnimation { fullScreen = true } } label: { Label("Editar HUD", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity).padding(.vertical, 13).glassButton() }
                    }.font(.subheadline.weight(.semibold))
                }.padding(16).glassPanel()
                Text("La vista previa usa imágenes reales del servidor cuando se conecta. Para jugar con baja latencia, más adelante se puede sustituir el refresco de imágenes por streaming de vídeo.").font(.caption).foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 2)
            }.padding(.horizontal, 16).padding(.bottom, 18)
        }
    }

    private var controlTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ENERGÍA").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.5))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    powerButton("Apagar", icon: "power", action: "shutdown", color: .red)
                    powerButton("Reiniciar", icon: "arrow.clockwise", action: "restart", color: .orange)
                    powerButton("Suspender", icon: "moon.zzz.fill", action: "sleep", color: .indigo)
                    powerButton("Bloquear", icon: "lock.fill", action: "lock", color: .white)
                }
                Button { sendWakeOnLAN() } label: { Label("Enviar Wake-on-LAN", systemImage: "bolt.fill").frame(maxWidth: .infinity).padding(16).glassButton() }.font(.subheadline.weight(.semibold))
                Text("Wake-on-LAN requiere configurar BIOS/UEFI y Windows. Esta app puede enviar el paquete de red, pero no puede garantizar que todo equipo lo admita.").font(.caption).foregroundStyle(.white.opacity(0.45))
                Text("RATÓN Y TECLADO").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.5)).padding(.top, 10)
                VStack(spacing: 12) {
                    HStack {
                        Button { Task { await client.sendMouse(x: 0.5, y: 0.5, button: "left") } } label: { Label("Clic izquierdo", systemImage: "cursorarrow.click").frame(maxWidth: .infinity).padding(12).glassButton() }
                        Button { Task { await client.sendMouse(x: 0.5, y: 0.5, button: "right") } } label: { Label("Clic derecho", systemImage: "cursorarrow.rays").frame(maxWidth: .infinity).padding(12).glassButton() }
                    }.font(.caption.weight(.medium))
                    HStack { ForEach([("Vol −", "VOLUME_DOWN"), ("Silenciar", "VOLUME_MUTE"), ("Vol +", "VOLUME_UP")], id: \.1) { title, key in Button(title) { Task { await client.sendKey(key) } }.frame(maxWidth: .infinity).padding(12).glassButton().font(.caption.weight(.semibold)) } }
                }
                Text(client.statusText).font(.caption).foregroundStyle(.white.opacity(0.5))
            }.padding(16)
        }
    }

    private var settingsTab: some View {
        Form {
            Section("Conexión") {
                TextField("IP de Windows (ej. 192.168.1.20)", text: $client.host).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("PIN del servidor", text: $client.pin).keyboardType(.numberPad)
                Button("Guardar y probar conexión") { Task { await client.testConnection() } }
            }
            Section("Mandos") {
                HStack { Text("Estado del mando"); Spacer(); Text(controller.connected ? "Conectado" : "No conectado").foregroundStyle(controller.connected ? .green : .secondary) }
                Text("La detección depende de mandos compatibles con GameController de iOS.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Controles táctiles") {
                Button("Editar distribución en pantalla completa") { editing = true; fullScreen = true }
                Button("Restablecer distribución", role: .destructive) { resetControls() }
            }
        }.scrollContentBackground(.hidden).foregroundStyle(.white)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            tabButton("Screen", icon: "display", index: 0)
            tabButton("Control", icon: "gamecontroller", index: 1)
            tabButton("Ajustes", icon: "gearshape", index: 2)
        }.padding(7).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.16))).padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 8)
    }

    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { tab = index } } label: {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 17, weight: .medium)); Text(title).font(.system(size: 10, weight: .semibold)) }
                .foregroundStyle(tab == index ? .white : .white.opacity(0.5)).frame(maxWidth: .infinity).padding(.vertical, 9).background { if tab == index { Capsule().fill(.white.opacity(0.15)).overlay(Capsule().stroke(.white.opacity(0.16))) } }
        }.buttonStyle(.plain)
    }

    private var gameScreen: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let frame = client.latestFrame { Image(uiImage: frame).resizable().aspectRatio(contentMode: .fit).frame(width: geo.size.width, height: geo.size.height).clipped() }
                else { VStack(spacing: 8) { Image(systemName: "display").font(.largeTitle); Text("Esperando pantalla de la PC").font(.headline); Text("Conectá el servidor para ver la imagen real.").font(.caption).foregroundStyle(.white.opacity(0.55)) }.foregroundStyle(.white.opacity(0.7)) }
                if modeGame && !controller.connected {
                    ForEach(controls) { control in
                        controlView(control, in: geo.size)
                    }
                }
                VStack {
                    HStack {
                        Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { fullScreen = false; editing = false } } label: { Image(systemName: "chevron.down").padding(12).glassButton() }
                        Spacer()
                        if editing { Text("EDITAR HUD").font(.caption.weight(.bold)).tracking(1).padding(10).glassButton() }
                        Button { editing.toggle() } label: { Image(systemName: editing ? "checkmark" : "slider.horizontal.3").padding(12).glassButton() }
                    }.padding(12)
                    Spacer()
                    if editing {
                        HStack {
                            Button { addControl() } label: { Label("Agregar", systemImage: "plus").padding(12).glassButton() }
                            Button { showingSettings = true } label: { Label("Conexión", systemImage: "network").padding(12).glassButton() }
                        }.padding(.bottom, 20)
                    }
                }
            }.ignoresSafeArea().statusBarHidden(true)
        }
    }

    private func controlView(_ control: TouchControl, in size: CGSize) -> some View {
        let binding = Binding<TouchControl>(get: { controls.first(where: { $0.id == control.id }) ?? control }, set: { updated in if let index = controls.firstIndex(where: { $0.id == control.id }) { controls[index] = updated; saveLayout() } })
        return Text(control.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).frame(width: control.size, height: control.size).background(.ultraThinMaterial, in: Circle()).opacity(0.45 + (control.opacity * 0.55)).overlay(Circle().stroke(.white.opacity(0.45))).position(x: control.x * size.width, y: control.y * size.height).gesture(DragGesture().onChanged { value in if editing { binding.wrappedValue.x = min(0.96, max(0.04, value.translation.width / size.width + control.x)); binding.wrappedValue.y = min(0.94, max(0.06, value.translation.height / size.height + control.y)) } }.onEnded { _ in if !editing { Task { await client.sendKey(control.key) } } }).onTapGesture { if editing { editingControl = ControlEditRequest(id: control.id) } else { Task { await client.sendKey(control.key) } } }.contextMenu { Button("Editar tamaño y función") { editingControl = ControlEditRequest(id: control.id) }; Button("Eliminar", role: .destructive) { controls.removeAll { $0.id == control.id }; saveLayout() } }
    }

    private func powerButton(_ title: String, icon: String, action: String, color: Color) -> some View {
        Button { Task { await client.action(action) } } label: { VStack(alignment: .leading, spacing: 14) { Image(systemName: icon).font(.title2).foregroundStyle(color); Text(title).font(.headline); Text("Enviar orden a Windows").font(.caption2).foregroundStyle(.white.opacity(0.45)) }.frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).padding(15).glassPanel() }.buttonStyle(.plain)
    }

    private var connectionSheet: some View {
        NavigationStack {
            Form {
                Section("Servidor de Windows") {
                    TextField("Dirección IP", text: $client.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("PIN", text: $client.pin)
                    Button("Guardar y probar") { Task { await client.testConnection() } }
                    Text(client.statusText).font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("El iPhone y la PC deben estar en la misma red local para esta versión inicial. No expongas el servidor directamente a Internet.").font(.caption) }
            }.navigationTitle("Conexión").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { client.saveSettings(); showingSettings = false } } }
        }.presentationDetents([.medium, .large])
    }

    private func controlEditor(id: UUID) -> some View {
        let index = controls.firstIndex(where: { $0.id == id })
        return NavigationStack {
            Form {
                if let index {
                    Section("Botón") {
                        TextField("Nombre", text: $controls[index].title)
                        TextField("Tecla (ej. SPACE, E, SHIFT)", text: $controls[index].key).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        VStack(alignment: .leading) { Text("Tamaño: \(Int(controls[index].size)) pt"); Slider(value: $controls[index].size, in: 36...110, step: 2) }
                        VStack(alignment: .leading) { Text("Transparencia: \(Int(controls[index].opacity * 100))%"); Slider(value: $controls[index].opacity, in: 0.15...1, step: 0.05) }
                        Button("Eliminar control", role: .destructive) { controls.removeAll { $0.id == id }; saveLayout(); editingControl = nil }
                    }
                }
            }.navigationTitle("Editar control").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { saveLayout(); editingControl = nil } } }
        }.presentationDetents([.medium, .large])
    }

    private func addControl() {
        let count = controls.count + 1
        controls.append(TouchControl(title: "BTN\(count)", key: "SPACE", x: 0.5, y: 0.5, size: 58, opacity: 0.62))
        saveLayout()
    }
    private func resetControls() {
        controls = [TouchControl(title: "A", key: "SPACE", x: 0.87, y: 0.69), TouchControl(title: "B", key: "E", x: 0.76, y: 0.53), TouchControl(title: "X", key: "R", x: 0.76, y: 0.82), TouchControl(title: "Y", key: "F", x: 0.88, y: 0.40)]
        saveLayout()
    }
    private func saveLayout() { if let data = try? JSONEncoder().encode(controls), let string = String(data: data, encoding: .utf8) { savedLayout = string } }
    private func loadLayout() { if let data = savedLayout.data(using: .utf8), let decoded = try? JSONDecoder().decode([TouchControl].self, from: data), !decoded.isEmpty { controls = decoded } }
    private func sendWakeOnLAN() { client.statusText = "Wake-on-LAN: requiere configurar la MAC de la PC y la red local." }
}

private extension View {
    func glassButton() -> some View { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.15))) }
    func glassPanel() -> some View { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.13))) }
}

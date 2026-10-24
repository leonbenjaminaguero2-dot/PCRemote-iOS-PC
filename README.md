# PC Remote (iOS + Windows companion)

Proyecto inicial para construir una app SwiftUI para iPhone y un servidor companion para Windows.

## Incluye
- SwiftUI: pestañas Screen, Control y Ajustes; vista previa; modo juego; HUD táctil con controles movibles; editor de tamaño/transparencia/tecla; detección básica de mandos iOS con GameController; conexión con PIN.
- Windows: servidor HTTP local en .NET 8 que entrega capturas JPEG, estado, acciones de energía, ratón y teclas permitidas.
- GitHub Actions para compilar un IPA sin firmar.

## Importante
Esta es una primera versión funcional de base, no una solución de streaming de baja latencia. La pantalla se obtiene mediante capturas JPEG periódicas; para juegos exigentes conviene implementar después streaming de vídeo de baja latencia. La detección del mando iOS solo oculta el HUD; aún no se transmite automáticamente cada botón físico al PC. Wake-on-LAN todavía necesita añadir la MAC de la PC y configurar BIOS/UEFI y red.

## Compilar la IPA desde GitHub
1. Subí todos los archivos de este proyecto a un repositorio.
2. Abrí Actions → Build PC Remote IPA → Run workflow.
3. Descargá el artefacto `PCRemote-unsigned-IPA`.

La IPA es sin firmar. Para instalarla necesitás firmarla con el método que uses (por ejemplo, SideStore/AltStore u otro firmador compatible).

## Servidor Windows
Requiere Windows 10/11 y .NET 8 SDK.
1. Abrí una terminal en `Windows/PCRemoteServer`.
2. Ejecutá `dotnet build -c Release`.
3. Ejecutá `dotnet run`.
4. Si Windows Firewall pregunta, permití acceso solo en redes privadas.
5. Copiá el PIN que muestra la consola y la IP local del PC en la app.

El servidor usa el puerto TCP 8765. No lo publiques en Internet ni hagas port-forwarding. Está pensado para la red local de confianza. Si Windows impide escuchar en la red, habrá que autorizar la URL/puerto o ajustar permisos del sistema.

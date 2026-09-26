# Trick Tiles

Tuzaklarla dolu, "zemine bile güvenme" temalı bir 2D platform oyunu. iOS 17+, Swift + SpriteKit + SwiftUI.
Türün ruhundan ilham alır; isim, görseller ve bölümler tamamen özgündür. Oyunda hiç görsel dosyası
yok: karakter, zemin, dikenler, kapı ve uygulama ikonu kodla çiziliyor.

- 10 bölüm: *Mind the Gap, Pop Goes the Floor, Runaway Door, Heads Up, Mirror Mirror, Leap of Faith,
  Squeeze, Run!, Patience, Trust Issues*
- Sabit 120 Hz simülasyon: zıplama 60 Hz ve ProMotion ekranlarda birebir aynı
- Ölümden sonra ~150 ms'de yeniden başlama, ölüm sayacı, kalıcı ilerleme ve en iyi süreler
- 5 ölümden sonra açılan **ipucu hayaleti**: bölümün kayıtlı çözümünü yarı saydam bir karakter oynar
- Dokunmatik (çoklu dokunuş), gamepad ve donanım klavyesi desteği
- Her bölümün çözülebilir olduğu otomatik olarak kanıtlanıyor (aşağıya bakın)

## Çalıştırma

1. Xcode 16 veya üstüyle `Game.xcodeproj` dosyasını açın.
2. `Game` şemasını seçip bir iPhone simülatöründe çalıştırın (⌘R).
3. Gerçek cihazda çalıştırmak için *Signing & Capabilities* altında kendi Team'inizi seçin.

Testler: Xcode'da ⌘U (GameCore testleri şemaya ekli) ya da terminalde:

```sh
swift test --package-path Packages/GameCore
```

### Kontroller

| | Dokunmatik | Klavye | Gamepad |
|---|---|---|---|
| Sol / sağ | Ekranın sol yarısı (sol ¼ sola, sonrası sağa) | ← → veya A D | D-pad / sol çubuk |
| Zıpla (basılı tut: daha yüksek) | Ekranın sağ yarısı | Boşluk, ↑, W | A / B |
| Duraklat | ⏸ düğmesi | Esc, P | Menu |
| Bölümü yeniden başlat | Duraklat menüsü | R | Y |

Dokunma alanları çizilen düğmelerden çok daha büyüktür; parmağınızı sol/sağ düğmeler arasında
kaydırarak yön değiştirebilirsiniz.

## Proje yapısı

```
Game.xcodeproj            project.yml'den üretilir (xcodegen generate)
project.yml               XcodeGen tanımı
Game/                     iOS uygulaması (SpriteKit + SwiftUI katmanı)
  App/                    GameApp, RootView, AppModel, GameViewModel
  Scene/                  GameScene, WorldNode, PlayerNode, efektler, prosedürel dokular, palet
  Input/                  InputRouter: dokunmatik + gamepad + klavye → tek InputState
  UI/                     Menü, bölüm seçimi, ayarlar, HUD, duraklat ve bitiş ekranları
  Debug/                  DebugOverlayNode (yalnızca DEBUG)
  Resources/              Assets.xcassets (ikon tools/make_icon.py ile çizildi)
Packages/GameCore/        Platformdan bağımsız oyun mantığı (Linux'ta da derlenir ve test edilir)
  Sources/GameCore/
    Core/                 Vec2/AABB, sabit timestep, InputState + InputLatch, EventBus, Constants
    Player/               PlayerState, PlayerController (coyote time, jump buffer, değişken zıplama)
    World/                Level (Codable), TileGrid, World, WorldBuilder, LevelCatalog
    Traps/                Trigger, Effect, Trap protokolü, TrapFactory, Effects/ (efekt başına bir dosya)
    Session/              Simulation, GameSession, InputReplay, LevelSolver
    Persistence/          ProgressStore (UserDefaults)
    Input/                TouchLayout / TouchTracker (dokunma alanı mantığı)
    Levels/               level_001.json … level_010.json, solutions/
  Sources/levelcheck/     Bölüm doğrulama / çözme / oynatma aracı
  Tests/GameCoreTests/    90+ birim ve uçtan uca test
```

Oyun mantığının tamamı `GameCore` paketinde, SpriteKit'e hiç bağımlı değil. `Simulation` bir değer
tipi: kopyalamak tüm oyun durumunun anlık görüntüsünü alır. Çözücü, ipucu hayaleti ve testler bunu
kullanıyor. SpriteKit katmanı yalnızca durumu okuyup çiziyor.

## Bölüm formatı

Bölümler `Packages/GameCore/Sources/GameCore/Levels/level_NNN.json` dosyalarıdır ve dosya adına göre
sıralanır. Kod değiştirmeden yeni bölüm eklemek için yeni bir dosya bırakmanız yeterli.

```json
{
  "id": "level_001",
  "name": "Mind the Gap",
  "tileSize": 32,
  "theme": 0,
  "grid": [
    "##########",
    "#........#",
    "#S......D#",
    "##########"
  ],
  "traps": [
    { "id": "floor_drop",
      "trigger": { "type": "zone", "rect": [5, 1, 2, 1] },
      "effect":  { "type": "collapse", "tiles": [[5, 0], [6, 0]] } }
  ]
}
```

Koordinatlar tile cinsinden, (0,0) sol alt köşe. Izgaranın solu ve sağı duvar sayılır; aşağıdan
düşmek ölümdür.

| Karakter | Anlamı |
|---|---|
| `#` | Duvar / zemin |
| `.` | Boş |
| `S` | Başlangıç noktası (tam bir tane) |
| `D` | Kapı (tam bir tane) |
| `^` `v` `<` `>` | Yukarı / aşağı / sola / sağa bakan diken |
| `x` | Sahte duvar: `#` gibi görünür, içinden geçilir |
| `?` | Gizli blok: katıdır ama dokunulana kadar görünmez |

### Tuzaklar

Her tuzak bir **tetikleyici** ve bir ya da daha fazla **efektten** oluşur (`"effect"` veya
`"effects": [...]`). İsteğe bağlı alanlar: `"once"` (varsayılan `true`) ve `"delay"` (tetiklenme ile
efekt arası saniye). Ateşlenen her tuzak `"<id>.fired"` olayını yayar; böylece tuzaklar zincirlenebilir.

| Tetikleyici | JSON |
|---|---|
| Oyuncu bölgeye girer | `{ "type": "zone", "rect": [x, y, w, h] }` |
| Bölüm başından beri geçen süre | `{ "type": "delay", "seconds": 2.5 }` |
| Başka bir tuzak / olay | `{ "type": "onEvent", "event": "floor_drop.fired" }` |

| Efekt | JSON |
|---|---|
| Zemin çöker | `{ "type": "collapse", "tiles": [[5,0]] }` |
| Diken çıkar | `{ "type": "spawnSpikes", "at": [[3,1]], "dir": "up" }` |
| Kapı kaçar | `{ "type": "moveDoor", "to": [20,5], "speed": 14 }` (0 = ışınlanır) |
| Tavan düşer (ezer) | `{ "type": "dropCeiling", "tiles": [[8,9]], "speed": 12 }` |
| Kontroller ters döner | `{ "type": "invertControls", "duration": 3 }` |
| Olay yayar | `{ "type": "emit", "event": "boom" }` |
| Duvar belirir | `{ "type": "addTiles", "tiles": [[4,1]] }` |
| Bloklar kayar (taşır / ezer) | `{ "type": "slideTiles", "tiles": [[10,1]], "by": [4,0], "speed": 6 }` |

Tile listesi alan her efektte `"tiles"` yerine `"rect": [x, y, w, h]` de yazılabilir.

Yeni efekt eklemek: `Effect` enum'una bir case, `Traps/Effects/` altına `TrapEffect`'e uyan tek dosya
ve `TrapFactory.makeEffect` içinde bir satır.

### Bölüm aracı: `levelcheck`

```sh
LC="swift run -c release --package-path Packages/GameCore levelcheck"
$LC validate                 # tüm bölümleri ayrıştır ve kontrol et
$LC render level_004         # ızgarayı tuzak bölgeleri ve hedefleriyle yazdır
$LC solve --write            # her bölüm için çözüm ara, Levels/solutions/ altına yaz
$LC replay --trace level_004 # kayıtlı çözümü adım adım oynat
$LC physics                  # zıplama yüksekliği, havada kalma süresi vb.
```

Çözücü, bölümü başsız (headless) simüle eden bir en-iyi-öncelikli aramadır. Testler her bölümün kayıtlı
çözümünün kapıya ulaştığını, bölümün beklemekle ya da sadece sağa basılı tutmakla geçilemediğini ve
tüm oyunun `GameSession` üzerinden baştan sona oynanabildiğini doğrular. Fizik veya bir bölüm
değişirse `levelcheck solve --write` yeniden çalıştırılır.

## Debug araçları (yalnızca DEBUG derlemeleri)

- **Overlay**: HUD'daki 🐞 düğmesi veya <kbd>`</kbd> tuşu. Tuzak bölgeleri, oyuncu/kapı/diken
  hitbox'ları, hareketli bloklar, FPS ve node sayısı.
- **Hot reload**: Simülatörde bölümler doğrudan kaynak klasörden okunur. JSON'u düzenleyin, HUD'daki
  ⟳ düğmesine veya <kbd>L</kbd>'ye basın.
- **Demo modu**: `-demoLevel 3` açılış argümanı 3. bölümü kayıtlı çözümle otomatik oynatır (CI ekran
  görüntüleri bununla alınıyor). `-debugOverlay YES` overlay'i açık başlatır.

## Sürekli entegrasyon

`.github/workflows/ci.yml`:

- **Linux**: `swift test`, bölüm doğrulama ve kayıtlı çözümlerin yeniden oynatılması
- **macOS**: Debug (simülatör) ve Release (cihaz) derlemesi, macOS'ta paket testleri, iOS
  simülatöründe testler ve her bölümden oynanış ekran görüntüleri (`screenshots` artifact'i)

## Plandan bilinçli sapmalar

- Oyun mantığı ayrı bir Swift paketi (`GameCore`) olarak yazıldı: SpriteKit'ten bağımsız, Linux'ta da
  test edilebiliyor ve CI'da iki platformda çalışıyor.
- `Trap` protokolü `AnyObject` değil, değer tipi. Tüm simülasyon kopyalanabilir olduğu için çözücü,
  ipucu hayaleti ve deterministik testler mümkün oldu. Yeniden başlatma yine plandaki gibi: dünya
  geri sarılmaz, önbellekteki `Level`'dan sıfırdan kurulur.
- `onEvent` zincirleri bir sonraki adımda (1/120 s sonra) tetiklenir; böylece zincirler tuzak
  sırasından bağımsız ve deterministik.
- Plandaki efektlere ek olarak `addTiles` ve `slideTiles`, ızgara sembollerine `v < > x ?` eklendi.

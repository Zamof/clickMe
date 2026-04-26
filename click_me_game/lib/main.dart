import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const ClickMeGameApp());
}

class ClickMeGameApp extends StatelessWidget {
  const ClickMeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Click Me Game',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const ClickMeGameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ClickMeGameScreen extends StatefulWidget {
  const ClickMeGameScreen({super.key});

  @override
  State<ClickMeGameScreen> createState() => _ClickMeGameScreenState();
}

class _ClickMeGameScreenState extends State<ClickMeGameScreen>
    with TickerProviderStateMixin {
  // Game state
  double _top = 100;
  double _left = 100;
  String _buttonText = 'Click me';
  int _score = 0;
  int _level = 1;
  int _lives = 3;
  bool _gameOver = false;
  bool _gamePaused = false;
  bool _isPowerUpActive = false;

  // Timers and animations
  Timer? _buttonTimer;
  Timer? _powerUpTimer;
  final Random _random = Random();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Animation controllers
  late AnimationController _buttonAnimationController;
  late AnimationController _scoreAnimationController;
  late AnimationController _shakeAnimationController;
  late Animation<double> _buttonScaleAnimation;
  late Animation<double> _scoreScaleAnimation;
  late Animation<double> _shakeAnimation;

  // UI state
  Color _backgroundColor = Colors.white;
  Color _buttonColor = Colors.blue;
  int _highScore = 0;
  double _buttonSize = 80;
  int _buttonDisplayTime = 3000;

  // Particle effects
  List<Particle> _particles = [];
  Timer? _particleTimer;

  // AdMob banner ad
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadHighScore();
    _loadBannerAd();

    // Set initial button position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _top = 200;
          _left = 100;
          _buttonText = 'Click me';
        });
        print('Initial button position set: (100, 200)');
        _startGameLoop();
      }
    });
  }

  void _initializeAnimations() {
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scoreAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _shakeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _scoreScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _scoreAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _shakeAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(
        parent: _shakeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  void _startGameLoop() {
    _buttonTimer?.cancel();
    _showNewButton();
  }

  void _showNewButton() {
    if (_gameOver || _gamePaused) return;

    final delay = Duration(
      milliseconds: 500 + _random.nextInt(_buttonDisplayTime),
    );

    _buttonTimer = Timer(delay, () {
      if (!mounted || _gameOver || _gamePaused) return;

      setState(() {
        _buttonText = _random.nextBool() ? 'Click me' : "Don't click me";

        // Get screen dimensions safely
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;

        // Ensure button stays within screen bounds with proper margins
        _top = 150 + _random.nextDouble() * (screenHeight - 300);
        _left = 50 + _random.nextDouble() * (screenWidth - 150);

        // Adjust difficulty based on level
        _buttonDisplayTime = max(800, 3000 - (_level * 200));
        _buttonSize = max(60, 100 - (_level * 5));

        _backgroundColor = _getRandomColor();
        _buttonColor = _getRandomColor();

        print(
          'Button moved to: (${_left.toStringAsFixed(1)}, ${_top.toStringAsFixed(1)}) - Text: $_buttonText',
        );
      });

      _buttonAnimationController.forward().then((_) {
        _buttonAnimationController.reverse();
      });

      // Continue the loop only if game is still active
      if (!_gameOver && !_gamePaused) {
        _showNewButton();
      }
    });
  }

  Color _getRandomColor() {
    // Generate vibrant colors using HSV
    final hue = _random.nextDouble() * 360;
    final saturation = 0.7 + _random.nextDouble() * 0.3;
    final value = 0.8 + _random.nextDouble() * 0.2;

    // Convert HSV to RGB
    final c = value * saturation;
    final x = c * (1 - ((hue / 60) % 2 - 1).abs());
    final m = value - c;

    double r, g, b;
    if (hue < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (hue < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (hue < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (hue < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (hue < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }

    return Color.fromARGB(
      255,
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
    );
  }

  void _handleClick() async {
    if (_buttonText == 'Click me') {
      _handleCorrectClick();
    } else {
      _handleWrongClick();
    }
  }

  void _handleCorrectClick() async {
    setState(() {
      _score++;
      if (_score % 10 == 0) {
        _level++;
        _lives = min(5, _lives + 1); // Bonus life every 10 points
      }
    });

    // Animate score
    _scoreAnimationController.forward().then((_) {
      _scoreAnimationController.reverse();
    });

    // Create particle effect
    _createParticles(
      _left + _buttonSize / 2,
      _top + _buttonSize / 2,
      Colors.green,
    );

    // Play sound
    await _audioPlayer.play(AssetSource('sounds/click.wav'));

    // Check for power-up activation
    if (_random.nextDouble() < 0.1) {
      // 10% chance
      _activatePowerUp();
    }
  }

  void _handleWrongClick() async {
    setState(() {
      _lives--;
      if (_lives <= 0) {
        _gameOver = true;
        _buttonTimer?.cancel();
      }
    });

    // Shake animation
    _shakeAnimationController.forward().then((_) {
      _shakeAnimationController.reverse();
    });

    // Create particle effect
    _createParticles(
      _left + _buttonSize / 2,
      _top + _buttonSize / 2,
      Colors.red,
    );

    if (_gameOver) {
      if (_score > _highScore) {
        _highScore = _score;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('high_score', _highScore);
      }
      await _audioPlayer.play(AssetSource('sounds/gameover.m4a'));
      _showGameOverDialog();
    } else {
      await _audioPlayer.play(AssetSource('sounds/click.wav'));
    }
  }

  void _activatePowerUp() {
    setState(() {
      _isPowerUpActive = true;
    });

    _powerUpTimer?.cancel();
    _powerUpTimer = Timer(const Duration(seconds: 5), () {
      setState(() {
        _isPowerUpActive = false;
      });
    });
  }

  void _createParticles(double x, double y, Color color) {
    for (int i = 0; i < 8; i++) {
      _particles.add(
        Particle(
          x: x,
          y: y,
          vx: (_random.nextDouble() - 0.5) * 200,
          vy: (_random.nextDouble() - 0.5) * 200,
          color: color,
          life: 1.0,
        ),
      );
    }

    _particleTimer?.cancel();
    _particleTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      setState(() {
        _particles.removeWhere((particle) {
          particle.update();
          return particle.life <= 0;
        });
      });

      if (_particles.isEmpty) {
        timer.cancel();
      }
    });
  }

  void _resetGame() {
    setState(() {
      _score = 0;
      _level = 1;
      _lives = 3;
      _gameOver = false;
      _gamePaused = false;
      _isPowerUpActive = false;
      _backgroundColor = Colors.white;
      _buttonColor = Colors.blue;
      _buttonSize = 80;
      _buttonDisplayTime = 3000;
      _particles.clear();
    });
    _startGameLoop();
  }

  void _togglePause() {
    setState(() {
      _gamePaused = !_gamePaused;
    });

    if (_gamePaused) {
      _buttonTimer?.cancel();
      print('Game paused - timer cancelled');
    } else {
      // Resume the game loop by starting a new button cycle
      if (!_gameOver) {
        print('Game resumed - starting new button cycle');
        _showNewButton();
      } else {
        print('Cannot resume - game is over');
      }
    }
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          "Game Over!",
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Final Score: $_score",
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              "Level Reached: $_level",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (_score > _highScore) ...[
              const SizedBox(height: 10),
              const Text(
                "🎉 New High Score! 🎉",
                style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetGame();
            },
            child: const Text(
              "Play Again",
              style: TextStyle(color: Colors.blue, fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _buttonTimer?.cancel();
    _powerUpTimer?.cancel();
    _particleTimer?.cancel();
    _buttonAnimationController.dispose();
    _scoreAnimationController.dispose();
    _shakeAnimationController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_backgroundColor, _backgroundColor.withValues(alpha: 0.8)],
          ),
        ),
        child: Stack(
          children: [
            // Game UI
            _buildGameUI(),

            // Particles
            ..._particles.map((particle) => particle.build()),

            // Power-up indicator
            if (_isPowerUpActive) _buildPowerUpIndicator(),

            // Pause overlay
            if (_gamePaused) _buildPauseOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildGameUI() {
    return Column(
      children: [
        // App bar with game info
        Container(
          padding: const EdgeInsets.only(
            top: 50,
            left: 20,
            right: 20,
            bottom: 20,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Score and level
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _scoreScaleAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scoreScaleAnimation.value,
                          child: Text(
                            "Score: $_score",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(2, 2),
                                  blurRadius: 4,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                    Text(
                      "Level: $_level",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 2,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // High score
              Expanded(
                flex: 2,
                child: Text(
                  "High: $_highScore",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 2,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Lives and pause button
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Lives
                      ...List.generate(5, (index) {
                        return Container(
                          margin: const EdgeInsets.only(right: 2),
                          child: Icon(
                            index < _lives
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: index < _lives ? Colors.red : Colors.white54,
                            size: 16,
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      // Pause button
                      IconButton(
                        onPressed: _togglePause,
                        icon: Icon(
                          _gamePaused ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Game area
        Expanded(
          child: Stack(
            children: [
              // Game button
              if (!_gameOver && !_gamePaused)
                Positioned(
                  top: _top,
                  left: _left,
                  child: AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          _shakeAnimation.value * (_random.nextDouble() - 0.5),
                          _shakeAnimation.value * (_random.nextDouble() - 0.5),
                        ),
                        child: AnimatedBuilder(
                          animation: _buttonScaleAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _buttonScaleAnimation.value,
                              child: Container(
                                width: _buttonSize,
                                height: _buttonSize,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    _buttonSize / 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _buttonColor.withValues(
                                        alpha: 0.6,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(
                                      _buttonSize / 2,
                                    ),
                                    onTap: _handleClick,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          _buttonSize / 2,
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            _buttonColor,
                                            _buttonColor.withValues(alpha: 0.8),
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _buttonText,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                offset: Offset(1, 1),
                                                blurRadius: 2,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        // Banner ad
        if (_isBannerAdLoaded)
          Container(
            height: _bannerAd!.size.height.toDouble(),
            width: double.infinity,
            child: AdWidget(ad: _bannerAd!),
          ),
      ],
    );
  }

  Widget _buildPowerUpIndicator() {
    return Positioned(
      top: 100,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.yellow.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.yellow.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flash_on, color: Colors.orange),
            SizedBox(width: 5),
            Text(
              "POWER UP, ENJOY!!",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePause,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pause_circle_outline, size: 100, color: Colors.white),
              SizedBox(height: 20),
              Text(
                "GAME PAUSED",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "Tap the pause button to resume",
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _highScore = prefs.getInt('high_score') ?? 0;
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId:
          'ca-app-pub-3940256099942544/6300978111', // Test banner ad unit ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('Ad failed to load: $error');
        },
      ),
    );
    _bannerAd!.load();
  }
}

class Particle {
  double x, y, vx, vy;
  Color color;
  double life;
  static const double gravity = 500;
  static const double friction = 0.98;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
  });

  void update() {
    x += vx * 0.016; // 60 FPS
    y += vy * 0.016;
    vy += gravity * 0.016;
    vx *= friction;
    vy *= friction;
    life -= 0.02;
  }

  Widget build() {
    return Positioned(
      left: x - 4,
      top: y - 4,
      child: Opacity(
        opacity: life,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

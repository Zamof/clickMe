import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';
import 'consent_manager.dart';

enum GameMode { endless, timed }

enum ButtonType { clickMe, dontClickMe, bonus, shieldButton, trap }

enum PowerUpType { doubleScore, slowMotion, shield }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // MobileAds is initialized later, once the consent check allows ads.
  // During development, configure a test device and use the Google-provided
  // test banner ad unit so AdMob serves test ads on your phone. Replace
  // 'TEST_DEVICE_ID' with the ID printed in your debug logs when an ad
  // request runs (or leave empty to only use the test unit id).
  if (kDebugMode) {
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: <String>['TEST_DEVICE_ID']),
    );
  }
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
  final Random _random = Random();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _showMenu = true;
  bool _gameOver = false;
  bool _gamePaused = false;
  bool _soundOn = true;

  GameMode _selectedMode = GameMode.endless;
  ButtonType _buttonType = ButtonType.clickMe;
  PowerUpType? _activePowerUp;

  int _score = 0;
  int _level = 1;
  int _lives = 3;
  int _combo = 0;
  int _highestCombo = 0;
  int _shieldCharges = 0;
  int _buttonDisplayTime = 2200;
  int _remainingTime = 60;

  int _highScoreEndless = 0;
  int _highScoreTimed = 0;

  double _top = 200;
  double _left = 100;
  double _buttonSize = 90;
  Color _backgroundColor = Colors.white;
  Color _buttonColor = Colors.blueAccent;

  Timer? _buttonTimer;
  Timer? _powerUpTimer;
  Timer? _gameTimer;
  Timer? _particleTimer;

  late AnimationController _buttonScaleController;
  late Animation<double> _buttonScaleAnimation;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  List<Particle> _particles = [];

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  // Keeps the game button away from the banner, so fast tapping can't land on
  // the ad by accident (AdMob treats accidental clicks as invalid traffic).
  static const double _adClearance = 48;
  static const double _minButtonTop = 120;
  final GlobalKey _gameAreaKey = GlobalKey();

  bool _adsStarted = false;
  bool _showPrivacyOptions = false;

  bool _missionScore20 = false;
  bool _missionCombo5 = false;
  bool _missionLevel3 = false;
  bool _missionSelectedScore20 = false;
  bool _missionSelectedCombo5 = false;
  bool _missionSelectedLevel3 = false;
  bool _powerUpShieldTimerActive = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadHighScores();
    ConsentManager.gatherConsent(_onConsentChanged);
  }

  Future<void> _onConsentChanged() async {
    final showPrivacyOptions = await ConsentManager.isPrivacyOptionsRequired();
    if (!mounted) return;
    setState(() {
      _showPrivacyOptions = showPrivacyOptions;
    });

    // This runs more than once, so make sure ads only start the first time.
    final canRequestAds = await ConsentManager.canRequestAds();
    if (_adsStarted || !canRequestAds) return;
    _adsStarted = true;
    await MobileAds.instance.initialize();
    if (mounted) _loadBannerAd();
  }

  void _initializeAnimations() {
    _buttonScaleController = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _buttonScaleController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 16.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  int get _currentMultiplier => min(1 + (_combo ~/ 5), 4);

  String get _modeLabel {
    return _selectedMode == GameMode.endless ? 'Endless' : 'Timed';
  }

  String _buttonLabel(ButtonType type) {
    switch (type) {
      case ButtonType.clickMe:
        return 'Click me';
      case ButtonType.dontClickMe:
        return 'Don\'t click me';
      case ButtonType.bonus:
        return 'Bonus!';
      case ButtonType.shieldButton:
        return 'Shield';
      case ButtonType.trap:
        return 'Trap!';
    }
  }

  Color _buttonTypeColor(ButtonType type) {
    switch (type) {
      case ButtonType.clickMe:
        return Colors.blue.shade700;
      case ButtonType.dontClickMe:
        return Colors.red.shade700;
      case ButtonType.bonus:
        return Colors.purple.shade700;
      case ButtonType.shieldButton:
        return Colors.teal.shade700;
      case ButtonType.trap:
        return Colors.orange.shade900;
    }
  }

  String _powerUpLabel(PowerUpType type) {
    switch (type) {
      case PowerUpType.doubleScore:
        return 'Double Score';
      case PowerUpType.slowMotion:
        return 'Slow Motion';
      case PowerUpType.shield:
        return 'Shield';
    }
  }

  void _startGame() {
    _resetGameState();
    setState(() {
      _showMenu = false;
      _gameOver = false;
      _gamePaused = false;
      _remainingTime = _selectedMode == GameMode.timed ? 60 : 0;
    });
    _moveButton();
    _scheduleNextButton();
    if (_selectedMode == GameMode.timed) {
      _startGameTimer();
    }
  }

  void _resetGameState() {
    _buttonTimer?.cancel();
    _gameTimer?.cancel();
    _powerUpTimer?.cancel();
    _particleTimer?.cancel();

    setState(() {
      _score = 0;
      _level = 1;
      _lives = 3;
      _combo = 0;
      _highestCombo = 0;
      _shieldCharges = 0;
      _buttonSize = 90;
      _buttonDisplayTime = 2200;
      _backgroundColor = Colors.white;
      _buttonColor = Colors.blueAccent;
      _activePowerUp = null;
      _powerUpSecondsLeft = 5;
      _powerUpShieldTimerActive = false;
      _particles.clear();
      _missionScore20 = false;
      _missionCombo5 = false;
      _missionLevel3 = false;
    });
  }

  void _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _highScoreEndless = prefs.getInt('high_score_endless') ?? 0;
      _highScoreTimed = prefs.getInt('high_score_timed') ?? 0;
    });
  }

  void _saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedMode == GameMode.endless) {
      if (_score > _highScoreEndless) {
        _highScoreEndless = _score;
        prefs.setInt('high_score_endless', _highScoreEndless);
      }
    } else {
      if (_score > _highScoreTimed) {
        _highScoreTimed = _score;
        prefs.setInt('high_score_timed', _highScoreTimed);
      }
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint('Banner ad failed to load: $error');
          }
        },
      ),
    );
    _bannerAd!.load();
  }

  void _scheduleNextButton() {
    _buttonTimer?.cancel();
    if (_gameOver || _gamePaused) return;

    final displayTime =
        _buttonDisplayTime +
        (_activePowerUp == PowerUpType.slowMotion ? 900 : 0);
    _buttonTimer = Timer(Duration(milliseconds: displayTime), () {
      if (!mounted || _gameOver || _gamePaused) return;
      _moveButton();
      _scheduleNextButton();
    });
  }

  void _startGameTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_gamePaused || _gameOver) return;
      setState(() {
        _remainingTime = max(0, _remainingTime - 1);
      });
      if (_remainingTime == 0) {
        timer.cancel();
        _finishGame();
      }
    });
  }

  void _moveButton() {
    final screenSize = MediaQuery.of(context).size;
    final maxLeft = screenSize.width - 120;
    final buttonSize = max<double>(70, 110 - (_level * 4));

    // The button is positioned inside the game area, which ends where the
    // banner starts, so measure that area rather than the whole screen.
    final gameAreaHeight =
        _gameAreaKey.currentContext?.size?.height ?? screenSize.height - 260;
    final maxTop = gameAreaHeight - buttonSize - _adClearance;

    setState(() {
      _buttonType = _chooseButtonType();
      _top =
          _minButtonTop +
          _random.nextDouble() * max(0, maxTop - _minButtonTop);
      _left = 24 + _random.nextDouble() * max(0, maxLeft - 24);
      _buttonSize = buttonSize;
      _buttonDisplayTime = max(900, 2200 - (_level * 170));
      _backgroundColor = _generateColor();
      _buttonColor = _buttonTypeColor(_buttonType);
    });

    _buttonScaleController.forward().then((_) {
      _buttonScaleController.reverse();
    });
  }

  ButtonType _chooseButtonType() {
    final chance = _random.nextDouble();
    if (chance < 0.50) return ButtonType.clickMe;
    if (chance < 0.72) return ButtonType.dontClickMe;
    if (chance < 0.87) return ButtonType.bonus;
    if (chance < 0.94) return ButtonType.shieldButton;
    return ButtonType.trap;
  }

  Color _generateColor() {
    final hue = _random.nextDouble() * 360;
    final saturation = 0.68 + _random.nextDouble() * 0.22;
    final value = 0.82 + _random.nextDouble() * 0.18;
    return HSVColor.fromAHSV(1, hue, saturation, value).toColor();
  }

  void _handleClick() {
    if (_gameOver || _gamePaused) return;
    if (_buttonType == ButtonType.clickMe ||
        _buttonType == ButtonType.bonus ||
        _buttonType == ButtonType.shieldButton) {
      _handleCorrectClick();
    } else {
      _handleWrongClick();
    }
  }

  void _handleCorrectClick() {
    final basePoints = _buttonType == ButtonType.bonus
        ? 3
        : _buttonType == ButtonType.shieldButton
        ? 2
        : 1;
    final points = basePoints * _currentMultiplier;

    setState(() {
      _score += points;
      _combo += 1;
      _highestCombo = max(_highestCombo, _combo);
      _buttonColor = Colors.greenAccent.shade700;
      _buttonDisplayTime = max(900, 2200 - (_level * 170));
      if (_score >= 20) _missionScore20 = true;
      if (_combo >= 5) _missionCombo5 = true;
      while (_score >= _level * 10) {
        _level += 1;
        if (_level % 3 == 0 && _lives < 5) {
          _lives += 1;
        }
      }
      if (_level >= 3) _missionLevel3 = true;
      if (_buttonType == ButtonType.shieldButton) {
        _shieldCharges += 1;
      }
    });

    _createParticles(Colors.green.shade400);
    _buttonScaleController.forward().then((_) {
      _buttonScaleController.reverse();
    });
    _playSound('sounds/click.wav');

    if (_activePowerUp == null && _random.nextDouble() < 0.18) {
      _activateRandomPowerUp();
    }

    _moveButton();
  }

  void _handleWrongClick() {
    if (_shieldCharges > 0) {
      setState(() {
        _shieldCharges -= 1;
        _buttonColor = Colors.cyan.shade700;
      });
      _createParticles(Colors.cyan.shade300);
      _playSound('sounds/click.wav');
      return;
    }

    setState(() {
      final damage = _buttonType == ButtonType.trap ? 2 : 1;
      _lives = max(0, _lives - damage);
      _combo = 0;
      _buttonColor = Colors.redAccent.shade700;
      if (_lives <= 0) {
        _gameOver = true;
        _buttonTimer?.cancel();
      }
    });

    _createParticles(Colors.red.shade400);
    _shakeController.forward().then((_) {
      _shakeController.reverse();
    });
    _playSound(_gameOver ? 'sounds/gameover.m4a' : 'sounds/click.wav');

    if (_gameOver) {
      _finishGame();
    } else {
      _moveButton();
    }
  }

  void _activateRandomPowerUp() {
    final powerUps = PowerUpType.values;
    final powerUp = powerUps[_random.nextInt(powerUps.length)];
    setState(() {
      _activePowerUp = powerUp;
    });

    if (powerUp == PowerUpType.shield) {
      _shieldCharges += 1;
      _powerUpShieldTimerActive = true;
    }

    _powerUpTimer?.cancel();
    _powerUpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _powerUpTimerTick();
      });
    });
  }

  int _powerUpSecondsLeft = 5;

  void _powerUpTimerTick() {
    _powerUpSecondsLeft = max(0, _powerUpSecondsLeft - 1);
    if (_powerUpSecondsLeft == 0) {
      _powerUpTimer?.cancel();
      if (_activePowerUp == PowerUpType.shield && _powerUpShieldTimerActive) {
        if (_shieldCharges > 0) {
          _shieldCharges -= 1;
        }
        _powerUpShieldTimerActive = false;
      }
      _activePowerUp = null;
      _powerUpSecondsLeft = 5;
    }
  }

  void _finishGame() {
    if (!_gameOver) {
      setState(() {
        _gameOver = true;
      });
    }
    _saveHighScore();
    _showGameOverDialog();
  }

  void _playSound(String assetPath) {
    if (!_soundOn) return;
    _audioPlayer.play(AssetSource(assetPath));
  }

  void _createParticles(Color color) {
    final centerX = _left + _buttonSize / 2;
    final centerY = _top + _buttonSize / 2;
    for (var i = 0; i < 12; i++) {
      _particles.add(
        Particle(
          x: centerX,
          y: centerY,
          vx: (_random.nextDouble() - 0.5) * 180,
          vy: (_random.nextDouble() - 0.5) * 180,
          color: color,
        ),
      );
    }

    _particleTimer?.cancel();
    _particleTimer = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _particles.removeWhere((particle) => particle.update());
      });
      if (_particles.isEmpty) {
        timer.cancel();
      }
    });
  }

  void _togglePause() {
    if (_gameOver) return;
    setState(() {
      _gamePaused = !_gamePaused;
    });
    if (_gamePaused) {
      _buttonTimer?.cancel();
      _gameTimer?.cancel();
    } else {
      _scheduleNextButton();
      if (_selectedMode == GameMode.timed) {
        _startGameTimer();
      }
    }
  }

  void _returnToMenu() {
    _buttonTimer?.cancel();
    _gameTimer?.cancel();
    _powerUpTimer?.cancel();
    _particleTimer?.cancel();
    setState(() {
      _showMenu = true;
      _gamePaused = false;
      _gameOver = false;
    });
  }

  void _showGameOverDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Game Over', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Score: $_score',
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                'Level: $_level',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                'Mode: $_modeLabel',
                style: const TextStyle(color: Colors.white70),
              ),
              if ((_selectedMode == GameMode.endless
                  ? _score > _highScoreEndless
                  : _score > _highScoreTimed)) ...[
                const SizedBox(height: 8),
                const Text(
                  '🎉 New High Score!',
                  style: TextStyle(color: Colors.amber),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _returnToMenu();
              },
              child: const Text('Menu'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startGame();
              },
              child: const Text('Play Again'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _buttonTimer?.cancel();
    _powerUpTimer?.cancel();
    _gameTimer?.cancel();
    _particleTimer?.cancel();
    _buttonScaleController.dispose();
    _shakeController.dispose();
    _bannerAd?.dispose();
    _audioPlayer.dispose();
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
            colors: _showMenu
                ? [
                    const Color.fromARGB(255, 48, 59, 177),
                    const Color.fromARGB(255, 54, 116, 146),
                  ]
                : [_backgroundColor, _backgroundColor.withValues(alpha: 0.8)],
          ),
        ),
        child: Stack(
          children: [
            if (_showMenu) _buildMenu(),
            if (!_showMenu) _buildGameBoard(),
            ..._particles.map((particle) => particle.build()),
            if (_activePowerUp != null) _buildPowerUpBadge(),
            if (!_showMenu && _gamePaused) _buildPauseOverlay(),
            if (!_showMenu && !_gameOver)
              Positioned(
                top: 50,
                left: 22,
                child: IconButton(
                  onPressed: _toggleSound,
                  icon: Icon(
                    _soundOn ? Icons.volume_up : Icons.volume_off,
                    color: const Color.fromARGB(255, 133, 96, 96),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleSound() {
    setState(() {
      _soundOn = !_soundOn;
    });
  }

  Widget _buildMenu() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Click Me',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select mode, choose missions, then tap play.',
                      style: TextStyle(
                        color: const Color.fromARGB(179, 183, 209, 205),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildModeSelector(),
                    const SizedBox(height: 24),
                    _buildMissionPanel(),
                    const SizedBox(height: 24),
                    _buildHighScorePanel(),
                    const SizedBox(height: 24),
                    _buildInstructionsPanel(),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (_showPrivacyOptions)
              Center(
                child: TextButton(
                  onPressed: ConsentManager.showPrivacyOptions,
                  child: const Text(
                    'Privacy settings',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            SafeArea(top: false, bottom: true, child: _buildButtonsRow()),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeChip(GameMode.endless, 'Endless'),
        const SizedBox(width: 12),
        _buildModeChip(GameMode.timed, 'Timed'),
      ],
    );
  }

  Widget _buildModeChip(GameMode mode, String label) {
    final selected = _selectedMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.blueAccent,
      backgroundColor: Colors.white24,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color.fromARGB(179, 173, 96, 96),
        fontWeight: FontWeight.bold,
      ),
      onSelected: (_) {
        setState(() {
          _selectedMode = mode;
        });
      },
    );
  }

  Widget _buildMissionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Missions',
            style: TextStyle(
              color: Color.fromARGB(255, 187, 191, 211),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildMissionRow(
            'Score 20 points in one game',
            _missionScore20,
            _missionSelectedScore20,
            () => _toggleMissionSelection(1),
          ),
          _buildMissionRow(
            'Build a combo of 5',
            _missionCombo5,
            _missionSelectedCombo5,
            () => _toggleMissionSelection(2),
          ),
          _buildMissionRow(
            'Reach level 3',
            _missionLevel3,
            _missionSelectedLevel3,
            () => _toggleMissionSelection(3),
          ),
        ],
      ),
    );
  }

  Widget _buildMissionRow(
    String label,
    bool complete,
    bool selected,
    VoidCallback onTap,
  ) {
    final icon = complete
        ? selected
              ? Icons.check_circle
              : Icons.check_circle_outline
        : selected
        ? Icons.check_box
        : Icons.check_box_outline_blank;
    final iconColor = complete
        ? Colors.greenAccent
        : selected
        ? Colors.lightBlueAccent
        : Colors.white54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: complete || selected ? Colors.white : Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleMissionSelection(int missionId) {
    setState(() {
      if (missionId == 1) {
        _missionSelectedScore20 = !_missionSelectedScore20;
      } else if (missionId == 2) {
        _missionSelectedCombo5 = !_missionSelectedCombo5;
      } else if (missionId == 3) {
        _missionSelectedLevel3 = !_missionSelectedLevel3;
      }
    });
  }

  Widget _buildInstructionsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'How It Works',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Text(
            '• Tap the active button and avoid wrong targets.',
            style: TextStyle(
              color: Color.fromARGB(179, 210, 217, 226),
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '• Build combos to increase your score multiplier.',
            style: TextStyle(
              color: Color.fromARGB(179, 210, 217, 226),
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '• Power-ups appear randomly and last for a short time.',
            style: TextStyle(
              color: Color.fromARGB(179, 210, 217, 226),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighScorePanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Best Scores',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Endless', style: TextStyle(color: Colors.white70)),
              Text(
                '$_highScoreEndless',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Timed', style: TextStyle(color: Colors.white70)),
              Text(
                '$_highScoreTimed',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _startGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Play',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGameBoard() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(
            top: 50,
            left: 20,
            right: 20,
            bottom: 20,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.20),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Score: $_score',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Combo: $_combo x$_currentMultiplier',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedMode == GameMode.timed)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Time: $_remainingTime',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Mode: $_modeLabel',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  if (_selectedMode == GameMode.endless)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Mode: $_modeLabel',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'High: ${_selectedMode == GameMode.endless ? _highScoreEndless : _highScoreTimed}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < _lives ? Icons.favorite : Icons.favorite_border,
                          color: i < _lives ? Colors.red : Colors.white54,
                          size: 18,
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: _togglePause,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _gamePaused ? Icons.play_arrow : Icons.pause,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _returnToMenu,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.home,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            key: _gameAreaKey,
            children: [
              if (!_gameOver && !_gamePaused)
                Positioned(
                  top: _top,
                  left: _left,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _buttonScaleController,
                      _shakeController,
                    ]),
                    builder: (context, child) {
                      final shake =
                          _shakeAnimation.value * (_random.nextDouble() - 0.5);
                      return Transform.translate(
                        offset: Offset(shake, shake),
                        child: Transform.scale(
                          scale: _buttonScaleAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: _buttonSize,
                      height: _buttonSize,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_buttonSize),
                          ),
                          backgroundColor: _buttonColor,
                          elevation: 14,
                          shadowColor: _buttonColor.withValues(alpha: 0.5),
                        ),
                        onPressed: _handleClick,
                        child: Text(
                          _buttonLabel(_buttonType),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_isBannerAdLoaded && _bannerAd != null)
          // SafeArea keeps the ad clear of the phone's navigation bar.
          SafeArea(
            top: false,
            child: SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          ),
      ],
    );
  }

  Widget _buildPowerUpBadge() {
    if (_activePowerUp == null && _shieldCharges == 0) {
      return const SizedBox.shrink();
    }

    final icon = _activePowerUp == PowerUpType.doubleScore
        ? Icons.score
        : _activePowerUp == PowerUpType.slowMotion
        ? Icons.slow_motion_video
        : Icons.shield;
    final label = _activePowerUp != null
        ? '${_powerUpLabel(_activePowerUp!)} ($_powerUpSecondsLeft)s'
        : 'Shield Ready';

    return Positioned(
      top: 96,
      right: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.yellow.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.yellow.withValues(alpha: 0.22),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _togglePause,
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill, size: 100, color: Colors.white),
                SizedBox(height: 18),
                Text(
                  'GAME PAUSED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Tap anywhere to resume',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  final Color color;
  double opacity = 1.0;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
  });

  bool update() {
    x += vx * 0.016;
    y += vy * 0.016;
    vy += 220 * 0.016;
    vx *= 0.97;
    vy *= 0.97;
    opacity -= 0.025;
    return opacity <= 0;
  }

  Widget build() {
    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.8),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

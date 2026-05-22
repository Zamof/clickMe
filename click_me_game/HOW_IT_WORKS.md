# Click Me Game — How It Works

## Overview
This game is a fast-paced reflex clicker built with Flutter. The player taps the active button while avoiding wrong targets, collects power-ups, and tries to beat their high score.

## Game Modes
- **Endless**: Keep playing until you lose all lives.
- **Timed**: Score as much as possible within a 60-second run.

## Button Types
- **Click me**: Normal target, gives points.
- **Don't click me**: Dangerous target, costs a life if pressed.
- **Bonus!**: High-value target, gives extra points.
- **Shield**: Grants temporary protection from one wrong tap.
- **Trap!**: Penalizes the player if tapped.

## Scoring and Combo
- Each correct button press increases your score.
- Consecutive correct taps build a combo.
- Every 5 correct taps increases your score multiplier up to `x4`.
- The game gets faster and smaller as you level up.

## Power-ups
Power-ups appear randomly:
- **Double Score**: Earn double points for a short time.
- **Slow Motion**: Buttons stay visible longer, making the game easier.
- **Shield**: Absorbs the next wrong tap.

Power-up status is displayed on screen with a timer.

## Progression and Feedback
- The level increases every 10 points.
- Every 3 levels, you earn an extra life (up to 5 lives).
- Visual feedback includes particle effects, button animation, and a level message.
- A main menu shows game instructions, selectable modes, and mission progress.

## Missions
The menu tracks three missions:
- Score 20 points in one game.
- Build a combo of 5.
- Reach level 3.

## High Scores
- The game saves separate best scores for **Endless** and **Timed** play.
- The high score is shown on the menu and the game over dialog.

## Controls
- Tap the button to interact.
- Use the pause button to pause and resume.
- Toggle sound on/off from the menu.

## Notes for Developers
- The game logic is implemented in `lib/main.dart`.
- Sounds are loaded from `assets/sounds/click.wav` and `assets/sounds/gameover.m4a`.
- A banner ad is included with Google Mobile Ads.

## Running the App
1. Open the `click_me_game` Flutter project.
2. Run `flutter pub get`.
3. Launch the app with `flutter run` or through your IDE.

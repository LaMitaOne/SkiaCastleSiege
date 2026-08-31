# SkiaCastleSiege
A physics-based siege prototype written in Delphi using Skia4Delphi. It features a slingshot-style catapult with independent projectile mechanics, destructible cross-section castle walls, and structural integrity simulation.

***Skia Castle Siege Catapult v 0.1***    
            
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/SkiaCastleSiege)    
     
<img width="659" height="480" alt="Unbenannt" src="https://github.com/user-attachments/assets/f3907aa8-797d-4c29-b892-1cde43fd0ce0" />
        
✨ Features     
   
Physics & Mechanics     
     
     Slingshot Aiming: Pull back with the mouse to aim. The drag distance and direction dictate the launch velocity (inverted).
     Trajectory Prediction: Real-time dotted parabola overlay that perfectly matches the stone's actual flight path.
     Catapult Arm Animation: Smooth, independent swing mechanics. The arm shoots forward, stays up while the stone flies, and only returns to the loaded position after the stone is destroyed.
     
World & Destruction    
    
     Destructible Cross-Section Walls: The castle is built from a grid of individual cells. The stone destroys cells within a specific blast radius upon impact.
     Structural Integrity: Wall cells automatically check for support. If the underlying blocks are destroyed, floating blocks will dynamically fall to the ground using gravity.
     Procedural Layout: The castle, towers, and king's room are generated programmatically with varying heights and wall gaps.
    
Visuals & UI    
     
     Particle System: Gravity-affected explosions spawning fire, smoke, and debris upon impact.
     Victory Screen: A large, dimmed overlay displaying "VICTORY!" when the King is hit, followed by an automated 3-second level reset.
     Custom Drawing: All graphics (catapult, walls, background) are strictly rendered using the Skia Canvas API (Paths, Paints, Translations, Rotations).
     
🎮 Controls    
     Aim	Hold Left Mouse Button   
     Fire	Release Left Mouse Button   
     Reset Level	R   
      

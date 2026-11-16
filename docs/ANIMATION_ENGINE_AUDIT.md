# Native animation engine audit

The iOS client already renders the duel with EDOPro's Irrlicht pipeline. The
existing card state includes translation, three-axis rotation, alpha fades,
attack markers, target/chain/equip markers and the `DrawSpec` overlay animation.
`MoveCard` and `FadeCard` update these states without a second render loop.

The native patch extends that pipeline with a time-based outline pulse:

- cyan for movement and summon/effect resolution;
- green for target, chain target and equip states;
- blue for attack state.

No additional animation engine is needed. Adding SceneKit, SpriteKit, Spine or
Unity would duplicate the render loop, add iOS dependency/linker work and make
the existing card coordinate/hit-test path harder to verify. Future visual work
should continue to use Irrlicht transforms, `DrawSpec`, existing symbol
textures and the current `aniFrame` state.

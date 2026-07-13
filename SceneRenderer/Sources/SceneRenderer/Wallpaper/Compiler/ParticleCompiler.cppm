module;

export module sr.pkg.parse:wp_particle_parser;
import rstd.cppstd;
import sr.json;
import sr.scene;
import sr.fs;

export import sr.pkg.scene_obj;

export namespace sr

{
class WPParticleParser {
public:
    static ParticleInitOp genParticleInitOp(const Json&);
    static ParticleOperatorOp
    genParticleOperatorOp(const Json&, std::shared_ptr<const wpscene::ParticleInstanceoverride>);
    static ParticleEmittOp genParticleEmittOp(const wpscene::Emitter&, bool sort = false);
    static ParticleInitOp
        genOverrideInitOp(std::shared_ptr<const wpscene::ParticleInstanceoverride>);
};
} // namespace sr

module;

#include <nlohmann/json.hpp>

export module sr.scene:visibility;
import rstd.cppstd;

export namespace sr
{

// Mirrors `sr::wpscene::VisibleUserBinding` (the schema-side type) but lives
// in the scene model so render-runtime code can resolve visibility against
// engine.userProperties without depending on `sr.pkg.scene_obj`. Populated by
// the scene compiler via `ToSceneUserVisibilityBinding`.
struct SceneUserVisibilityBinding {
    std::string    key;
    nlohmann::json condition;
    bool           has_condition { false };

    bool empty() const { return key.empty(); }
};

// WE user-properties may be wrapped as `{"value": <scalar>}` or stored bare.
// Returns the payload to compare against a binding's condition.
inline const nlohmann::json& SceneUserPropertyPayload(const nlohmann::json& property) {
    if (property.is_object()) {
        auto it = property.find("value");
        if (it != property.end()) return *it;
    }
    return property;
}

inline std::optional<std::string> SceneJsonScalarString(const nlohmann::json& value) {
    if (value.is_string()) return value.get<std::string>();
    if (value.is_boolean()) return value.get<bool>() ? "true" : "false";
    if (value.is_number_integer()) return std::to_string(value.get<std::int64_t>());
    if (value.is_number_unsigned()) return std::to_string(value.get<std::uint64_t>());
    if (value.is_number_float()) {
        std::ostringstream os;
        os << value.get<double>();
        return os.str();
    }
    return std::nullopt;
}

inline bool SceneJsonScalarEquals(const nlohmann::json& a, const nlohmann::json& b) {
    if (a == b) return true;
    auto as = SceneJsonScalarString(a);
    auto bs = SceneJsonScalarString(b);
    if (! as || ! bs) return false;
    if (*as == *bs) return true;
    if (a.is_boolean() && b.is_string()) {
        const auto s = b.get<std::string>();
        return (a.get<bool>() && s == "1") || (! a.get<bool>() && s == "0");
    }
    if (a.is_string() && b.is_boolean()) {
        const auto s = a.get<std::string>();
        return (b.get<bool>() && s == "1") || (! b.get<bool>() && s == "0");
    }
    return false;
}

// Resolves a binding against a single user-property payload. Returns nullopt
// when the binding is empty or the payload cannot coerce to a bool.
inline std::optional<bool>
ResolveSceneUserVisibilityBinding(const SceneUserVisibilityBinding& binding,
                                  const nlohmann::json&             property) {
    if (binding.empty()) return std::nullopt;
    const auto& value = SceneUserPropertyPayload(property);
    if (binding.has_condition) return SceneJsonScalarEquals(value, binding.condition);
    if (value.is_boolean()) return value.get<bool>();
    return std::nullopt;
}

// Resolves a binding against a (key, property) pair from the user-property
// map. Returns nullopt when the binding's key does not match `key` or the
// payload cannot coerce.
inline std::optional<bool>
ResolveSceneUserVisibilityBinding(const SceneUserVisibilityBinding& binding, std::string_view key,
                                  const nlohmann::json& property) {
    if (binding.key != key) return std::nullopt;
    return ResolveSceneUserVisibilityBinding(binding, property);
}

} // namespace sr

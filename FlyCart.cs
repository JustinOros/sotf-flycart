using System.Globalization;
using System.Text;
using RedLoader;
using RedLoader.Utils;
using Sons.Gameplay;
using SonsSdk;
using SonsSdk.Attributes;
using TheForest.Utils;
using UnityEngine;
using Object = UnityEngine.Object;

namespace FlyCart;

public class FlyCart : SonsMod
{
    const float SearchInterval = 0.5f;
    const float SearchRadius = 2.5f;

    static FlyCart _instance;

    GolfCartController _cart;
    Rigidbody _body;
    readonly List<WheelCollider> _wheels = new();

    bool _flying;
    float _searchTimer;
    bool _inputFailed;

    float _speed = 22f;
    float _climb = 10f;
    float _turn = 70f;
    float _tilt = 14f;
    float _accel = 2.5f;

    float _yaw;
    float _savedDrag;
    float _savedAngularDrag;
    bool _savedGravity;
    RigidbodyConstraints _savedConstraints;

    public FlyCart()
    {
        _instance = this;
        OnUpdateCallback = Tick;
    }

    protected override void OnSdkInitialized()
    {
        RLog.Msg("FlyCart 1.0.0 loaded. Sit in a golf cart and use the console commands: flycart on, flycart off. Others: flycartspeed, flycartdump");
    }

    protected override void OnGameStart()
    {
        StopFlying();
    }

    void Tick()
    {
        if (!_flying) return;

        if (LocalPlayer.Transform == null || _body == null || !IsInCart(_body))
        {
            StopFlying();
            return;
        }

        Fly(Time.deltaTime);
    }

    bool FindCart()
    {
        _cart = null;
        _body = null;

        var player = LocalPlayer.Transform;
        if (player == null) return false;

        var root = player.root;
        if (root != player && TryUseCart(root.GetComponentInChildren<GolfCartController>())) return true;

        foreach (var col in Physics.OverlapSphere(player.position, SearchRadius, ~0, QueryTriggerInteraction.Ignore))
        {
            if (col == null) continue;
            if (TryUseCart(col.GetComponentInParent<GolfCartController>())) return true;
        }

        return false;
    }

    bool TryUseCart(GolfCartController cart)
    {
        if (cart == null) return false;

        var body = cart.GetComponentInParent<Rigidbody>();
        if (body == null) body = cart.GetComponentInChildren<Rigidbody>();
        if (body == null || !IsInCart(body)) return false;

        _cart = cart;
        _body = body;
        return true;
    }

    bool IsInCart(Rigidbody body)
    {
        var player = LocalPlayer.Transform;
        if (player.IsChildOf(body.transform.root)) return true;
        return Vector3.Distance(player.position, body.position) < 1.8f;
    }

    void StartFlying()
    {
        if (!FindCart())
        {
            RLog.Msg("FlyCart: sit in a golf cart first");
            return;
        }

        _wheels.Clear();
        foreach (var w in _body.transform.root.GetComponentsInChildren<WheelCollider>(true))
            if (w != null) _wheels.Add(w);

        _savedGravity = _body.useGravity;
        _savedDrag = _body.drag;
        _savedAngularDrag = _body.angularDrag;
        _savedConstraints = _body.constraints;

        _body.useGravity = false;
        _body.drag = 0.5f;
        _body.angularDrag = 4f;
        _body.WakeUp();
        _yaw = _body.rotation.eulerAngles.y;

        foreach (var w in _wheels) w.enabled = false;

        _flying = true;
        RLog.Msg($"FlyCart on. W/S forward and back, A/D turn, Space up, Left Ctrl down. Wheels={_wheels.Count}");
    }

    void StopFlying()
    {
        if (!_flying && _body == null) return;
        _flying = false;

        if (_body != null)
        {
            _body.useGravity = _savedGravity;
            _body.drag = _savedDrag;
            _body.angularDrag = _savedAngularDrag;
            _body.constraints = _savedConstraints;
            _body.WakeUp();
        }

        foreach (var w in _wheels)
            if (w != null) w.enabled = true;
        _wheels.Clear();

        _body = null;
        _cart = null;
        RLog.Msg("FlyCart off");
    }

    void Fly(float dt)
    {
        float fwd = 0f, turn = 0f, vert = 0f;
        try
        {
            if (Input.GetKey(KeyCode.W)) fwd += 1f;
            if (Input.GetKey(KeyCode.S)) fwd -= 1f;
            if (Input.GetKey(KeyCode.D)) turn += 1f;
            if (Input.GetKey(KeyCode.A)) turn -= 1f;
            if (Input.GetKey(KeyCode.Space)) vert += 1f;
            if (Input.GetKey(KeyCode.LeftControl)) vert -= 1f;
        }
        catch (Exception e)
        {
            if (!_inputFailed)
            {
                _inputFailed = true;
                RLog.Error("FlyCart: input read failed: " + e.Message);
            }
        }

        _yaw += turn * _turn * dt;

        var yawRot = Quaternion.Euler(0f, _yaw, 0f);
        var target = Quaternion.Euler(fwd * _tilt, _yaw, 0f);
        _body.rotation = Quaternion.Slerp(_body.rotation, target, Mathf.Clamp01(dt * 3f));
        _body.angularVelocity = Vector3.zero;

        var wanted = yawRot * Vector3.forward * (fwd * _speed) + Vector3.up * (vert * _climb);
        _body.velocity = Vector3.Lerp(_body.velocity, wanted, Mathf.Clamp01(dt * _accel));
    }

    [DebugCommand("flycart")]
    static void MainCommand(string args)
    {
        if (_instance == null) return;
        _instance.HandleMain(args);
    }

    void HandleMain(string args)
    {
        var arg = (args ?? "").Trim().ToLowerInvariant();
        if (arg == "on")
        {
            if (_flying) RLog.Msg("FlyCart is already on");
            else StartFlying();
            return;
        }
        if (arg == "off")
        {
            if (_flying) StopFlying();
            else RLog.Msg("FlyCart is already off");
            return;
        }
        RLog.Msg($"flycart <on|off>  current: {(_flying ? "on" : "off")}");
    }

    [DebugCommand("flycartspeed")]
    static void SpeedCommand(string args)
    {
        if (_instance == null) return;
        _instance.SetSpeed(args);
    }

    void SetSpeed(string args)
    {
        var parts = (args ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 3)
        {
            RLog.Msg($"flycartspeed <forward> <climb> <turn>  current: {_speed} {_climb} {_turn}");
            return;
        }
        _speed = float.Parse(parts[0], CultureInfo.InvariantCulture);
        _climb = float.Parse(parts[1], CultureInfo.InvariantCulture);
        _turn = float.Parse(parts[2], CultureInfo.InvariantCulture);
        RLog.Msg($"FlyCart speed set to {_speed} {_climb} {_turn}");
    }

    [DebugCommand("flycartdump")]
    static void DumpCommand(string args)
    {
        if (_instance == null) return;
        _instance.WriteDump();
    }

    void WriteDump()
    {
        var sb = new StringBuilder();
        var path = Path.Combine(LoaderEnvironment.UserDataDirectory, "FlyCartDump.txt");

        try
        {
            var cart = _cart != null ? _cart : NearestCart();
            if (cart == null)
            {
                RLog.Msg("FlyCart: no golf cart found");
                return;
            }

            sb.Append("GolfCartController on: ").AppendLine(cart.gameObject.name);
            var root = cart.transform.root;

            var body = cart.GetComponentInParent<Rigidbody>();
            if (body == null) body = cart.GetComponentInChildren<Rigidbody>();
            if (body != null)
                sb.AppendLine($"Rigidbody mass={body.mass} drag={body.drag} angularDrag={body.angularDrag} gravity={body.useGravity} kinematic={body.isKinematic} constraints={body.constraints}");

            sb.AppendLine();
            sb.AppendLine("HIERARCHY");
            Dump(root, 0, sb);

        }
        catch (Exception e)
        {
            sb.AppendLine("DUMP FAILED: " + e);
            RLog.Error("FlyCart dump failed: " + e);
        }

        File.WriteAllText(path, sb.ToString());
        RLog.Msg($"FlyCart dump written to {path}");
    }

    static string PathOf(Transform t)
    {
        var sb = new StringBuilder(t.name);
        var p = t.parent;
        var guard = 0;
        while (p != null && guard++ < 30)
        {
            sb.Insert(0, p.name + "/");
            p = p.parent;
        }
        return sb.ToString();
    }

    GolfCartController NearestCart()
    {
        GolfCartController best = null;
        var bestDist = float.MaxValue;
        var from = LocalPlayer.Transform != null ? LocalPlayer.Transform.position : Vector3.zero;
        foreach (var cart in Object.FindObjectsOfType<GolfCartController>())
        {
            var d = Vector3.Distance(from, cart.transform.position);
            if (d < bestDist)
            {
                bestDist = d;
                best = cart;
            }
        }
        return best;
    }

    void Dump(Transform t, int depth, StringBuilder sb)
    {
        var pad = new string(' ', depth * 2);
        sb.Append(pad).Append(t.name);
        if (!t.gameObject.activeInHierarchy) sb.Append(" (inactive)");
        sb.AppendLine();

        foreach (var c in t.GetComponents<Component>())
        {
            if (c == null) continue;
            try
            {
                sb.Append(pad).Append("  - ").AppendLine(c.GetIl2CppType().Name);
            }
            catch (Exception e)
            {
                sb.Append(pad).Append("  ! error: ").AppendLine(e.Message);
            }
        }

        for (int i = 0; i < t.childCount; i++) Dump(t.GetChild(i), depth + 1, sb);
    }
}

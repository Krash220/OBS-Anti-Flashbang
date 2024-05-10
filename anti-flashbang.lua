obs = obslua

EFFECT = nil
EFFECT_PARAMS = nil

SOURCE_INFO = {}
SOURCE_INFO.id = 'anti-flashbang'
SOURCE_INFO.type = obs.OBS_SOURCE_TYPE_FILTER
SOURCE_INFO.output_flags = obs.OBS_SOURCE_VIDEO

SOURCE_INFO.get_name = function()
    if obs.obs_get_locale() == 'zh-CN' then
        return '闪光画面过滤'
    else
        return 'Anti-Flashbang'
    end
end

SOURCE_INFO.create = function(settings, source)
    local filter = {}
    filter.source = source
    filter.run_first = true
    filter.last_render = get_time()
    obs.obs_enter_graphics()
    filter.downsampler = {}
    for i = 1, 7 do
        filter.downsampler[i] = obs.gs_texrender_create(obs.GS_RGBA16F, obs.GS_ZS_NONE)
    end
    filter.last = obs.gs_texrender_create(obs.GS_RGBA16F, obs.GS_ZS_NONE)
    obs.obs_leave_graphics()
    SOURCE_INFO.update(filter, settings)
    return filter
end

SOURCE_INFO.destroy = function(filter)
    obs.obs_enter_graphics()
    for i = 1, #filter.downsampler do
        obs.gs_texrender_destroy(filter.downsampler[i])
    end
    obs.gs_texrender_destroy(filter.last)
    obs.obs_leave_graphics()
end

SOURCE_INFO.get_properties = function(settings)
    props = obs.obs_properties_create()

    if obs.obs_get_locale() == 'zh-CN' then
        obs.obs_properties_add_float_slider(props, 'S', '过滤后饱和度', 0, 100, 0.1)
        obs.obs_properties_add_float_slider(props, 'V', '过滤后亮度', 0, 100, 0.1)
        obs.obs_properties_add_float_slider(props, 'T', '过滤后淡出时间', 1, 10, 0.1)
        obs.obs_properties_add_float_slider(props, 'TL', '较暗画面过滤淡出时间', 0.1, 10, 0.1)
    else
        obs.obs_properties_add_float_slider(props, 'S', 'Saturation', 0, 100, 0.1)
        obs.obs_properties_add_float_slider(props, 'V', 'Brightness', 0, 100, 0.1)
        obs.obs_properties_add_float_slider(props, 'T', 'Fade Time', 1, 10, 0.1)
        obs.obs_properties_add_float_slider(props, 'TL', 'Fade Time in dark', 0.01, 10, 0.1)
    end

    return props
end

function update_render_size(filter)
    target = obs.obs_filter_get_target(filter.source)

    local width, height
    if target == nil then
        width = 0
        height = 0
    else
        width = obs.obs_source_get_base_width(target)
        height = obs.obs_source_get_base_height(target)
    end

    filter.width = width
    filter.height = height
end

SOURCE_INFO.update = function(filter, settings)
    filter.S = obs.obs_data_get_double(settings, 'S')
    filter.V = obs.obs_data_get_double(settings, 'V')
    filter.T = obs.obs_data_get_double(settings, 'T')
    filter.TL = obs.obs_data_get_double(settings, 'TL')
    update_render_size(filter)
end

SOURCE_INFO.get_defaults = function(settings)
    obs.obs_data_set_default_double(settings, 'S', 10.0)
    obs.obs_data_set_default_double(settings, 'V', 25.0)
    obs.obs_data_set_default_double(settings, 'T', 5.0)
    obs.obs_data_set_default_double(settings, 'TL', 0.2)
end

SOURCE_INFO.get_width = function(filter)
    return filter.width
end

SOURCE_INFO.get_height = function(filter)
    return filter.height
end

function get_time()
    return obs.os_gettime_ns() / 1000000000.0
end

function down_sample(filter)
    local last_calc
    last_calc = obs.gs_texrender_get_texture(filter.last)

    local width, height, tech
    width = filter.width
    height = filter.height

    for i = 1, #filter.downsampler do
        tech = 'DownSample'
        if i == 1 then
            tech = 'DownSampleFirst'
        elseif i == #filter.downsampler then
            tech = 'DownSampleLast'
        end

        obs.gs_effect_set_int(EFFECT_PARAMS.last_width, width)
        obs.gs_effect_set_int(EFFECT_PARAMS.last_height, height)

        if i == #filter.downsampler then
            width = 1
            height = 1
        else
            width = math.ceil(width / 2.0)
            height = math.ceil(height / 2.0)
        end

        obs.gs_effect_set_int(EFFECT_PARAMS.width, width)
        obs.gs_effect_set_int(EFFECT_PARAMS.height, height)
        obs.gs_effect_set_bool(EFFECT_PARAMS.run_first, filter.run_first)
        obs.gs_effect_set_float(EFFECT_PARAMS.fadetime, filter.frametime / filter.T)
        obs.gs_effect_set_float(EFFECT_PARAMS.fadetimelow, filter.frametime / filter.TL)

        if last_calc ~= nil then
            if obs.gs_get_linear_srgb() then
                obs.gs_effect_set_texture_srgb(EFFECT_PARAMS.last_calc, last_calc)
            else
                obs.gs_effect_set_texture(EFFECT_PARAMS.last_calc, last_calc)
            end
        end

        obs.gs_texrender_reset(filter.downsampler[i])
        if obs.gs_texrender_begin(filter.downsampler[i], width, height) then
            obs.gs_ortho(0.0, width, 0.0, height, -100.0, 100.0)
            obs.obs_source_process_filter_tech_end(filter.source, EFFECT, width, height, tech)
            obs.gs_texrender_end(filter.downsampler[i])

            local img_calc
            img_calc = obs.gs_texrender_get_texture(filter.downsampler[i])
            if obs.gs_get_linear_srgb() then
                obs.gs_effect_set_texture_srgb(EFFECT_PARAMS.img_calc, img_calc)
            else
                obs.gs_effect_set_texture(EFFECT_PARAMS.img_calc, img_calc)
            end
        else
            return false
        end
    end

    filter.run_first = false
    filter.last, filter.downsampler[#filter.downsampler] = filter.downsampler[#filter.downsampler], filter.last

    return true
end

SOURCE_INFO.video_render = function(filter)
    time = get_time()
    filter.frametime = time - filter.last_render
    filter.last_render = time
    if not obs.obs_source_process_filter_begin(filter.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING) then
        obs.obs_source_skip_video_filter(filter.source)
        return
    end

    obs.gs_blend_state_push()
    obs.gs_blend_function_separate(obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO, obs.GS_BLEND_ONE, obs.GS_BLEND_ZERO)

    if down_sample(filter) then
        obs.gs_effect_set_float(EFFECT_PARAMS.saturation, 1.0 - filter.S / 100.0)
        obs.gs_effect_set_float(EFFECT_PARAMS.value, filter.V / 100.0)
        obs.obs_source_process_filter_end(filter.source, EFFECT, filter.width, filter.height)
    else
        obs.obs_source_process_filter_tech_end(filter.source, EFFECT, filter.width, filter.height, 'BitBlt')
    end

    obs.gs_blend_state_pop()
end

SOURCE_INFO.video_tick = function(filter, seconds)
    update_render_size(filter)
end

function create_effect_from_file(path)
    local effect, content
    effect = io.open(path, 'r')
    io.input(effect)
    content = io.read('*a')
    io.close()

    return obs.gs_effect_create(content, nil, nil)
end

function script_load(settings)
    obs.obs_enter_graphics()
    -- EFFECT = create_effect_from_file(script_path() .. 'anti-flashbang.effect')
    EFFECT = obs.gs_effect_create(effect_code, nil, nil)
    obs.obs_leave_graphics()

    if EFFECT ~= nil then
        obs.obs_register_source(SOURCE_INFO)
        EFFECT_PARAMS = {}
        EFFECT_PARAMS.last_width = obs.gs_effect_get_param_by_name(EFFECT, 'last_width')
        EFFECT_PARAMS.last_height = obs.gs_effect_get_param_by_name(EFFECT, 'last_height')
        EFFECT_PARAMS.width = obs.gs_effect_get_param_by_name(EFFECT, 'width')
        EFFECT_PARAMS.height = obs.gs_effect_get_param_by_name(EFFECT, 'height')
        EFFECT_PARAMS.last_calc = obs.gs_effect_get_param_by_name(EFFECT, 'last_calc')
        EFFECT_PARAMS.img_calc = obs.gs_effect_get_param_by_name(EFFECT, 'img_calc')
        EFFECT_PARAMS.run_first = obs.gs_effect_get_param_by_name(EFFECT, 'run_first')
        EFFECT_PARAMS.fadetime = obs.gs_effect_get_param_by_name(EFFECT, 'fadetime')
        EFFECT_PARAMS.fadetimelow = obs.gs_effect_get_param_by_name(EFFECT, 'fadetimelow')
        EFFECT_PARAMS.saturation = obs.gs_effect_get_param_by_name(EFFECT, 'saturation')
        EFFECT_PARAMS.value = obs.gs_effect_get_param_by_name(EFFECT, 'value')
    end
end

function script_unload()
    if EFFECT ~= nil then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(EFFECT)
        obs.obs_leave_graphics()
        EFFECT = nil
    end
end

effect_code = [[
uniform float4x4 ViewProj;
uniform texture2d image;

uniform int last_width;
uniform int last_height;
uniform int width;
uniform int height;
uniform bool run_first;

uniform float fadetime;
uniform float fadetimelow;
uniform float saturation;
uniform float value;

uniform texture2d img_calc;
uniform texture2d last_calc;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Border;
    AddressV  = Border;
    BorderColor = 00000000;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VS_Default(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

float4 PS_DownSampleFirst(VertData v_in) : TARGET
{
    int3 uv = int3(v_in.uv * float2(width, height), 0) * 2;

    float3 p0 = pow(image.Load(uv + int3(0, 0, 0)).rgb, float3(2.2, 2.2, 2.2));
    float3 p1 = pow(image.Load(uv + int3(1, 0, 0)).rgb, float3(2.2, 2.2, 2.2));
    float3 p2 = pow(image.Load(uv + int3(0, 1, 0)).rgb, float3(2.2, 2.2, 2.2));
    float3 p3 = pow(image.Load(uv + int3(1, 1, 0)).rgb, float3(2.2, 2.2, 2.2));

    return float4((p0 + p1 + p2 + p3) / 4.0, 1.0);
}

float4 PS_DownSample(VertData v_in) : TARGET
{
    int3 uv = int3(v_in.uv * float2(width, height), 0) * 2;

    float3 p0 = img_calc.Load(uv + int3(0, 0, 0)).rgb;
    float3 p1 = img_calc.Load(uv + int3(1, 0, 0)).rgb;
    float3 p2 = img_calc.Load(uv + int3(0, 1, 0)).rgb;
    float3 p3 = img_calc.Load(uv + int3(1, 1, 0)).rgb;

    return float4((p0 + p1 + p2 + p3) / 4.0, 1.0);
}

float4 PS_DownSampleLast(VertData v_in) : TARGET
{
    float4 result = float4(0.0, 0.0, 0.0, 0.0);

    for (int i = 0; i < last_width; i++)
    {
        for (int j = 0; j < last_height; j++)
        {
            float len = pow(max(0.0, 1.0 - length(float2((i + 0.5) / last_width, 0))), 0.5) * 2.0 + 1.0;
            result.rgb += img_calc.Load(int3(i, j, 0)).rgb * len;
        }
    }

    result.rgb *= 4.6;
    result.rgb /= float(last_width * last_height);
    float4 last = last_calc.Sample(textureSampler, float2(0.5, 0.5));

    if (run_first)
    {
        result.a = 0.0;
    }
    else
    {
        float sub = max(result.r - last.r, max(result.g - last.g, result.b - last.b));

        if (sub > 2.0)
        {
            result.a = max(min(1.0, max(0.1, (sub - 2.0) / 2.0)), last.a);
        }
        else if (result.r < 2.0 && result.g < 2.0 && result.b < 0.5)
        {
            result.a = max(0.0, last.a - fadetimelow);
        }
        else
        {
            result.a = max(0.0, last.a - fadetime);
        }
    }

    return result;
}

float4 PS_Main(VertData v_in) : TARGET
{
    float4 color = image.Sample(textureSampler, v_in.uv);
    float4 calc = img_calc.Sample(textureSampler, float2(0.5, 0.5));
    float max_channel = max(color.r, max(color.g, color.b));

    color.rgb = lerp(color.rgb, lerp(color.rgb, float3(max_channel, max_channel, max_channel), saturation) * value, calc.a * calc.a * (3.0 - 2.0 * calc.a));

    return color;
}

float4 PS_BitBlt(VertData v_in) : TARGET
{
    return image.Sample(textureSampler, v_in.uv);
}

technique DownSampleFirst
{
    pass
    {
        vertex_shader = VS_Default(v_in);
        pixel_shader  = PS_DownSampleFirst(v_in);
    }
}

technique DownSample
{
    pass
    {
        vertex_shader = VS_Default(v_in);
        pixel_shader  = PS_DownSample(v_in);
    }
}

technique DownSampleLast
{
    pass
    {
        vertex_shader = VS_Default(v_in);
        pixel_shader  = PS_DownSampleLast(v_in);
    }
}

technique Draw
{
    pass
    {
        vertex_shader = VS_Default(v_in);
        pixel_shader  = PS_Main(v_in);
    }
}

technique BitBlt
{
    pass
    {
        vertex_shader = VS_Default(v_in);
        pixel_shader  = PS_BitBlt(v_in);
    }
}
]]
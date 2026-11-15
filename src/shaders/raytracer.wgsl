const THREAD_COUNT = 16;
const RAY_TMIN = 0.0001;
const RAY_TMAX = 100.0;
const PI = 3.1415927f;
const FRAC_1_PI = 0.31830987f;
const FRAC_2_PI = 1.5707964f;

@group(0) @binding(0)  
  var<storage, read_write> fb : array<vec4f>;

@group(0) @binding(1)
  var<storage, read_write> rtfb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> spheresb : array<sphere>;

@group(2) @binding(1)
  var<storage, read_write> quadsb : array<quad>;

@group(2) @binding(2)
  var<storage, read_write> boxesb : array<box>;

@group(2) @binding(3)
  var<storage, read_write> trianglesb : array<triangle>;

@group(2) @binding(4)
  var<storage, read_write> meshb : array<mesh>;

struct ray {
  origin : vec3f,
  direction : vec3f,
};

struct sphere {
  transform : vec4f,
  color : vec4f,
  material : vec4f,
};

struct quad {
  Q : vec4f,
  u : vec4f,
  v : vec4f,
  color : vec4f,
  material : vec4f,
};

struct box {
  center : vec4f,
  radius : vec4f,
  rotation: vec4f,
  color : vec4f,
  material : vec4f,
};

struct triangle {
  v0 : vec4f,
  v1 : vec4f,
  v2 : vec4f,
};

struct mesh {
  transform : vec4f,
  scale : vec4f,
  rotation : vec4f,
  color : vec4f,
  material : vec4f,
  min : vec4f,
  max : vec4f,
  show_bb : f32,
  start : f32,
  end : f32,
};

struct material_behaviour {
  scatter : bool,
  direction : vec3f,
};

struct camera {
  origin : vec3f,
  lower_left_corner : vec3f,
  horizontal : vec3f,
  vertical : vec3f,
  u : vec3f,
  v : vec3f,
  w : vec3f,
  lens_radius : f32,
};

struct hit_record {
  t : f32,
  p : vec3f,
  normal : vec3f,
  object_color : vec4f,
  object_material : vec4f,
  frontface : bool,
  hit_anything : bool,
};

fn ray_at(r: ray, t: f32) -> vec3f
{
  return r.origin + t * r.direction;
}

fn get_ray(cam: camera, uv: vec2f, rng_state: ptr<function, u32>) -> ray
{
  var rd = cam.lens_radius * rng_next_vec3_in_unit_disk(rng_state);
  var offset = cam.u * rd.x + cam.v * rd.y;
  return ray(cam.origin + offset, normalize(cam.lower_left_corner + uv.x * cam.horizontal + uv.y * cam.vertical - cam.origin - offset));
}

fn get_camera(lookfrom: vec3f, lookat: vec3f, vup: vec3f, vfov: f32, aspect_ratio: f32, aperture: f32, focus_dist: f32) -> camera
{
  var camera = camera();
  camera.lens_radius = aperture / 2.0;

  var theta = degrees_to_radians(vfov);
  var h = tan(theta / 2.0);
  var w = aspect_ratio * h;

  camera.origin = lookfrom;
  camera.w = normalize(lookfrom - lookat);
  camera.u = normalize(cross(vup, camera.w));
  camera.v = cross(camera.u, camera.w);

  camera.lower_left_corner = camera.origin - w * focus_dist * camera.u - h * focus_dist * camera.v - focus_dist * camera.w;
  camera.horizontal = 2.0 * w * focus_dist * camera.u;
  camera.vertical = 2.0 * h * focus_dist * camera.v;

  return camera;
}

fn envoriment_color(direction: vec3f, color1: vec3f, color2: vec3f) -> vec3f
{
  var unit_direction = normalize(direction);
  var t = 0.5 * (unit_direction.y + 1.0);
  var col = (1.0 - t) * color1 + t * color2;

  var sun_direction = normalize(vec3(uniforms[13], uniforms[14], uniforms[15]));
  var sun_color = int_to_rgb(i32(uniforms[17]));
  var sun_intensity = uniforms[16];
  var sun_size = uniforms[18];

  var sun = clamp(dot(sun_direction, unit_direction), 0.0, 1.0);
  col += sun_color * max(0, (pow(sun, sun_size) * sun_intensity));

  return col;
}

fn check_ray_collision(r: ray, max_t: f32) -> hit_record
{
  let spheres_count = i32(uniforms[19]);
  let quads_count = i32(uniforms[20]);
  let boxes_count = i32(uniforms[21]);

  var closest = hit_record(
    min(max_t, RAY_TMAX),
    vec3f(0.0),
    vec3f(0.0),
    vec4f(0.0),
    vec4f(0.0),
    false,
    false
  );

  // Esferas
  for (var i = 0; i < spheres_count; i = i + 1) {
    var candidate = hit_record(
      closest.t,
      vec3f(0.0),
      vec3f(0.0),
      vec4f(0.0),
      vec4f(0.0),
      false,
      false
    );

    let sphere = spheresb[i];

    hit_sphere(
      sphere.transform.xyz,
      sphere.transform.w,
      r,
      &candidate,
      closest.t
    );

    if (candidate.hit_anything) {
      candidate.object_color = sphere.color;
      candidate.object_material = sphere.material;
      closest = candidate;
    }
  }

  // Quads
  for (var i = 0; i < quads_count; i = i + 1) {
    var candidate = hit_record(
      closest.t,
      vec3f(0.0),
      vec3f(0.0),
      vec4f(0.0),
      vec4f(0.0),
      false,
      false
    );

    let quad = quadsb[i];

    hit_quad(
      r,
      quad.Q,
      quad.u,
      quad.v,
      &candidate,
      closest.t
    );

    if (candidate.hit_anything) {
      candidate.frontface = dot(r.direction, candidate.normal) < 0.0;
      candidate.object_color = quad.color;
      candidate.object_material = quad.material;
      closest = candidate;
    }
  }

  // Caixas alinhadas aos eixos
  for (var i = 0; i < boxes_count; i = i + 1) {
    var candidate = hit_record(
      closest.t,
      vec3f(0.0),
      vec3f(0.0),
      vec4f(0.0),
      vec4f(0.0),
      false,
      false
    );

    let box_object = boxesb[i];

    hit_box(
      r,
      box_object.center.xyz,
      box_object.radius.xyz,
      &candidate,
      closest.t
    );

    if (candidate.hit_anything) {
      candidate.frontface = dot(r.direction, candidate.normal) < 0.0;
      candidate.object_color = box_object.color;
      candidate.object_material = box_object.material;
      closest = candidate;
    }
  }

  return closest;
}

fn lambertian(
  normal: vec3f,
  absorption: f32,
  random_sphere: vec3f,
  rng_state: ptr<function, u32>
) -> material_behaviour
{
  var direction = normal + random_sphere;

  // Evita uma direção quase nula.
  if (length(direction) < 0.0001) {
    direction = normal;
  }

  return material_behaviour(true, normalize(direction));
}

fn metal(normal : vec3f, direction: vec3f, fuzz: f32, random_sphere: vec3f) -> material_behaviour
{
  let reflected = reflect(normalize(direction), normal);

  // fuzz = 0 dá um reflexo nítido.
  // Valores maiores espalham o reflexo.
  let fuzz_amount = clamp(fuzz, 0.0, 1.0);
  var scattered = reflected + fuzz_amount * random_sphere;

  if (length(scattered) < 0.0001) {
    scattered = reflected;
  }

  scattered = normalize(scattered);

  // Se a direção apontar para dentro da superfície, não há espalhamento.
  let valid_scatter = dot(scattered, normal) > 0.0;

  return material_behaviour(valid_scatter, scattered);
}

fn dielectric(normal : vec3f, r_direction: vec3f, refraction_index: f32, frontface: bool, random_sphere: vec3f, fuzz: f32, rng_state: ptr<function, u32>) -> material_behaviour
{  
  let unit_direction = normalize(r_direction);

  // Ao entrar no material, o raio passa do ar para o vidro.
  // Ao sair, a razão se inverte.
  var eta = refraction_index;

  if (frontface) {
    eta = 1.0 / refraction_index;
  }

  let cos_theta = min(dot(-unit_direction, normal), 1.0);
  let sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));

  // Reflexão total interna: o raio não consegue atravessar.
  let cannot_refract = eta * sin_theta > 1.0;

  // Aproximação de Schlick para a chance de reflexão.
  let r0_base = (1.0 - refraction_index) / (1.0 + refraction_index);
  let r0 = r0_base * r0_base;
  let reflectance =
    r0 + (1.0 - r0) * pow(1.0 - cos_theta, 5.0);

  var direction: vec3f;

  if (cannot_refract || rng_next_float(rng_state) < reflectance) {
    direction = reflect(unit_direction, normal);
  } else {
    // Lei de Snell: calcula a direção refratada.
    let perpendicular =
      eta * (unit_direction + cos_theta * normal);

    let parallel =
      -sqrt(max(0.0, 1.0 - dot(perpendicular, perpendicular))) * normal;

    direction = perpendicular + parallel;
  }

  // Aplica uma pequena perturbação para vidro rugoso.
  direction += clamp(fuzz, 0.0, 1.0) * random_sphere;

  if (length(direction) < 0.0001) {
    direction = normal;
  }

  return material_behaviour(true, normalize(direction));
}

fn emmisive(color: vec3f, light: f32) -> material_behaviour
{
  // Reutiliza direction para transportar a cor emitida
  // até trace. Um material emissivo não espalha o raio.
  return material_behaviour(false, color * light);
}

fn trace(r: ray, rng_state: ptr<function, u32>) -> vec3f
{
  let max_bounces = i32(uniforms[2]);
  let background_color1 = int_to_rgb(i32(uniforms[11]));
  let background_color2 = int_to_rgb(i32(uniforms[12]));

  var current_ray = r;
  var throughput = vec3f(1.0);
  var accumulated_light = vec3f(0.0);

  for (var bounce = 0; bounce < max_bounces; bounce = bounce + 1) {
    let hit = check_ray_collision(current_ray, RAY_TMAX);

    if (!hit.hit_anything) {
      let sky = envoriment_color(
        current_ray.direction,
        background_color1,
        background_color2
      );

      accumulated_light += throughput * sky;
      break;
    }

    let random_direction = rng_next_vec3_in_unit_sphere(rng_state);
    let material = hit.object_material;

    var behaviour: material_behaviour;

    if (material.w > 0.0) {
      let emission = emmisive(hit.object_color.rgb, material.w);
      accumulated_light += throughput * emission.direction;
      break;
    }

    if (material.x < 0.0) {
      behaviour = dielectric(
        hit.normal,
        current_ray.direction,
        1.5,
        hit.frontface,
        random_direction,
        material.y,
        rng_state
      );
    }

    else if (material.x > 0.0) {
      behaviour = metal(
        hit.normal,
        current_ray.direction,
        material.y,
        random_direction
      );
    } else {
      behaviour = lambertian(
        hit.normal,
        material.y,
        random_direction,
        rng_state
      );
    }

    if (!behaviour.scatter) {
      break;
    }

    // A cor do objeto atenua a luz que continuará pelo caminho.
    let specular = clamp(material.z, 0.0, 1.0);
    let surface_color = mix(
      hit.object_color.rgb,
      vec3f(1.0),
      specular
    );

    if (material.x < 0.0) {
      throughput *= hit.object_color.rgb;
    } else {
      let specular = clamp(material.z, 0.0, 1.0);
      let surface_color = mix(
        hit.object_color.rgb,
        vec3f(1.0),
        specular
      );

      throughput *= surface_color;
    }

    current_ray = ray(
      hit.p + hit.normal * RAY_TMIN,
      behaviour.direction
    );
  }

  return accumulated_light;
}

@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
    var rez = uniforms[1];
    var time = u32(uniforms[0]);

    // init_rng (random number generator) we pass the pixel position, resolution and frame
    var rng_state = init_rng(vec2(id.x, id.y), vec2(u32(rez)), time);

    // Get uv
    var fragCoord = vec2f(f32(id.x), f32(id.y));
    var uv = (fragCoord + sample_square(&rng_state)) / vec2(rez);

    // Camera
    var lookfrom = vec3(uniforms[7], uniforms[8], uniforms[9]);
    var lookat = vec3(uniforms[23], uniforms[24], uniforms[25]);

    // Get camera
    var cam = get_camera(lookfrom, lookat, vec3(0.0, 1.0, 0.0), uniforms[10], 1.0, uniforms[6], uniforms[5]);
    var samples_per_pixel = i32(uniforms[4]);

    var color_sum = vec3f(0.0);

    for (var sample_index = 0; sample_index < samples_per_pixel; sample_index = sample_index + 1) {
      let sample_uv =
        (fragCoord + sample_square(&rng_state)) / vec2f(rez);

      let camera_ray = get_ray(cam, sample_uv, &rng_state);
      color_sum += trace(camera_ray, &rng_state);
    }

    var color = color_sum / f32(max(samples_per_pixel, 1));
    color = max(color, vec3f(0.0));

    let pixel_index = mapfb(id.xy, f32(rez));

    // A variável color ainda está em espaço linear aqui.
    var average_color = color;
    var sample_count = 1.0;

    if (uniforms[3] > 0.5) {
      let previous = rtfb[pixel_index];

      if (previous.w > 0.0) {
        sample_count = previous.w + 1.0;
        average_color =
          previous.rgb + (color - previous.rgb) / sample_count;
      }
    }

    // Guarda a média linear e o número de quadros acumulados.
    rtfb[pixel_index] = vec4f(average_color, sample_count);

    // O buffer exibido recebe a cor com correção gamma.
    fb[pixel_index] = vec4f(linear_to_gamma(average_color), 1.0);
}
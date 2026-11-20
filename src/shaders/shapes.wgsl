fn hit_sphere(
  center: vec3f,
  radius: f32,
  r: ray,
  record: ptr<function, hit_record>,
  max_t: f32
)
{
  let oc = r.origin - center;
  let a = dot(r.direction, r.direction);
  let half_b = dot(oc, r.direction);
  let c = dot(oc, oc) - radius * radius;
  let discriminant = half_b * half_b - a * c;

  if (discriminant < 0.0) {
    record.hit_anything = false;
    return;
  }

  let sqrt_discriminant = sqrt(discriminant);

  // Tenta primeiro a interseção mais próxima.
  var t = (-half_b - sqrt_discriminant) / a;

  // Se estiver atrás do raio ou além do objeto mais próximo,
  // tenta a outra interseção.
  if (t < RAY_TMIN || t > max_t) {
    t = (-half_b + sqrt_discriminant) / a;
  }

  if (t < RAY_TMIN || t > max_t) {
    record.hit_anything = false;
    return;
  }

  let point = ray_at(r, t);
  let outward_normal = (point - center) / radius;
  let frontface = dot(r.direction, outward_normal) < 0.0;

  record.t = t;
  record.p = point;
  record.normal = select(-outward_normal, outward_normal, frontface);
  record.frontface = frontface;
  record.hit_anything = true;
}

fn hit_quad(r: ray, Q: vec4f, u: vec4f, v: vec4f, record: ptr<function, hit_record>, max: f32)
{
  var n = cross(u.xyz, v.xyz);
  var normal = normalize(n);
  var D = dot(normal, Q.xyz);
  var w = n / dot(n.xyz, n.xyz);

  var denom = dot(normal, r.direction);
  if (abs(denom) < 0.0001)
  {
    record.hit_anything = false;
    return;
  }

  var t = (D - dot(normal, r.origin)) / denom;
  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  var intersection = ray_at(r, t);
  var planar_hitpt_vector = intersection - Q.xyz;
  var alpha = dot(w, cross(planar_hitpt_vector, v.xyz));
  var beta = dot(w, cross(u.xyz, planar_hitpt_vector));

  if (alpha < 0.0 || alpha > 1.0 || beta < 0.0 || beta > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  if (dot(normal, r.direction) > 0.0)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = intersection;
  record.normal = normal;
  record.hit_anything = true;
}

fn hit_triangle(r: ray, v0: vec3f, v1: vec3f, v2: vec3f, record: ptr<function, hit_record>, max: f32)
{
  var v1v0 = v1 - v0;
  var v2v0 = v2 - v0;
  var rov0 = r.origin - v0;

  var n = cross(v1v0, v2v0);
  var q = cross(rov0, r.direction);

  // Raio paralelo ao triângulo: sem interseção (evita divisão por zero / NaN).
  var denom = dot(r.direction, n);
  if (abs(denom) < 1e-12)
  {
    record.hit_anything = false;
    return;
  }

  var d = 1.0 / denom;

  var u = d * dot(-q, v2v0);
  var v = d * dot(q, v1v0);
  var t = d * dot(-n, rov0);

  if (u < 0.0 || u > 1.0 || v < 0.0 || (u + v) > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  record.normal = normalize(n);
  record.hit_anything = true;
}

fn hit_box(r: ray, center: vec3f, rad: vec3f, record: ptr<function, hit_record>, t_max: f32)
{
  var m = 1.0 / r.direction;
  var n = m * (r.origin - center);
  var k = abs(m) * rad;

  var t1 = -n - k;
  var t2 = -n + k;

  var tN = max(max(t1.x, t1.y), t1.z);
  var tF = min(min(t2.x, t2.y), t2.z);

  if (tN > tF || tF < 0.0)
  {
    record.hit_anything = false;
    return;
  }

  // Normal de entrada (aponta contra o raio).
  var t = tN;
  var normal = -sign(r.direction) * step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
  var frontface = true;

  // Origem dentro da caixa (ex.: raio refratado num vidro): usa a saída.
  if (t < RAY_TMIN)
  {
    t = tF;
    // Normal de saída (para fora), invertida para ficar contra o raio.
    normal = -sign(r.direction) * step(t2.xyz, t2.yzx) * step(t2.xyz, t2.zxy);
    frontface = false;
  }

  if (t < RAY_TMIN || t > t_max)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  record.normal = normal;
  record.frontface = frontface;
  record.hit_anything = true;

  return;
}

// Cilindro com tampas, alinhado ao eixo Y local, centrado na origem local.
// radius = raio, half_height = metade da altura.
fn hit_cylinder(r: ray, radius: f32, half_height: f32, record: ptr<function, hit_record>, t_max: f32)
{
  var best_t = t_max;
  var best_normal = vec3f(0.0);
  var found = false;

  // Lateral: x^2 + z^2 = radius^2
  let a = r.direction.x * r.direction.x + r.direction.z * r.direction.z;
  let half_b = r.origin.x * r.direction.x + r.origin.z * r.direction.z;
  let c = r.origin.x * r.origin.x + r.origin.z * r.origin.z - radius * radius;

  if (a > 1e-8)
  {
    let disc = half_b * half_b - a * c;
    if (disc >= 0.0)
    {
      let s = sqrt(disc);
      for (var k = 0; k < 2; k = k + 1)
      {
        let t = select((-half_b + s) / a, (-half_b - s) / a, k == 0);
        let y = r.origin.y + t * r.direction.y;
        if (t > RAY_TMIN && t < best_t && abs(y) <= half_height)
        {
          let p = ray_at(r, t);
          best_t = t;
          best_normal = vec3f(p.x, 0.0, p.z) / radius;
          found = true;
        }
      }
    }
  }

  // Tampas: y = +-half_height
  if (abs(r.direction.y) > 1e-8)
  {
    for (var k = 0; k < 2; k = k + 1)
    {
      let cap_y = select(-half_height, half_height, k == 0);
      let t = (cap_y - r.origin.y) / r.direction.y;
      if (t > RAY_TMIN && t < best_t)
      {
        let p = ray_at(r, t);
        if (p.x * p.x + p.z * p.z <= radius * radius)
        {
          best_t = t;
          best_normal = vec3f(0.0, sign(cap_y), 0.0);
          found = true;
        }
      }
    }
  }

  if (!found)
  {
    record.hit_anything = false;
    return;
  }

  let frontface = dot(r.direction, best_normal) < 0.0;

  record.t = best_t;
  record.p = ray_at(r, best_t);
  record.normal = select(-best_normal, best_normal, frontface);
  record.frontface = frontface;
  record.hit_anything = true;
}
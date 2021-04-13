// MaxSpeed - Igor "lonewolf" Kelvin <igorkelvin@gmail.com

#include <amxmodx>
#include <amxmisc>
#include <engine>
#include <fakemeta>
#include <xs>

#define PLUGIN  "MaxSpeed"
#define VERSION "0.9"
#define AUTHOR  "lonewolf"

new cvar_enabled;
new cvar_maxspeed;
new cvar_surfspeed;
new cvar_duckspeed;
new cvar_swimspeed;
new cvar_debug;
new cvar_noaccel;

new bool:enabled;
new Float:maxspeed;
new Float:surfspeed;
new Float:duckspeed;
new Float:swimspeed;

new debug_is_enabled;
new noaccel_flags;

new Float:user_oldspeed[33];
new Float:hud_time[33];

new bool:just_double_ducked[33];
new bool:just_surfed[33];
new bool:user_enabled_speed[33];

enum
{
  NOACCEL_AIR  = 1,
  NOACCEL_SWIM = 2,
  NOACCEL_SURF = 4
};

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);
  
  cvar_enabled   = create_cvar("amx_maxspeed_enabled",   "1",   _, "<0/1> Disable/Enable MaxSpeed Plugin");
  cvar_maxspeed  = create_cvar("amx_maxspeed",           "400", _, "<0-2000> Maximum airspeed");
  cvar_surfspeed = create_cvar("amx_maxspeed_surfspeed", "2000", _,"<0-2000> Maximum speed while surfing");
  cvar_duckspeed = create_cvar("amx_maxspeed_duckspeed", "300", _, "<0-2000> Maximum speed after double-ducking");
  cvar_swimspeed = create_cvar("amx_maxspeed_swimspeed", "400", _, "<0-2000> Maximum speed on water");
  cvar_debug     = create_cvar("amx_maxspeed_debug",     "0",   _, "<0/1> Enables /speed command");
  cvar_noaccel   = create_cvar("amx_maxspeed_noaccel",   "0",   _, "<0-7> Bitsum: 1-Airstrafe noaccel, 2-Swim noaccel, 4-Surf noaccel");
  
  bind_pcvar_num(cvar_enabled,     enabled);
  bind_pcvar_num(cvar_debug,       debug_is_enabled);
  bind_pcvar_num(cvar_noaccel,     noaccel_flags);
  bind_pcvar_float(cvar_maxspeed,  maxspeed);
  bind_pcvar_float(cvar_surfspeed, surfspeed);
  bind_pcvar_float(cvar_duckspeed, duckspeed);
  bind_pcvar_float(cvar_swimspeed, swimspeed);
  
  register_clcmd("say /speed", "handle_speed");
  
}

public client_connect(id)
{
  user_oldspeed[id]      = 0.0;
  just_double_ducked[id] = false;
  user_enabled_speed[id] = false;
  just_surfed[id]        = false;
}

public handle_speed(id)
{
  if (get_pcvar_num(cvar_debug))
  {
    user_enabled_speed[id] = !user_enabled_speed[id];
    client_print(id, print_chat, "Maxspeed plugin speed %s.", user_enabled_speed[id] ? "enabled" : "disabled");
  }
}


public client_cmdStart(id)
{
  
  if(!is_user_alive(id) || !enabled) 
  {
    return PLUGIN_CONTINUE;
  }
  
  new button     = get_usercmd(usercmd_buttons, button);
  new oldbutton  = get_user_oldbutton(id);
  
  new just_released = (oldbutton ^ button) & oldbutton;
  
  if (!(just_released & IN_DUCK))
  {
    return PLUGIN_CONTINUE;
  }
  
  new user_flags = get_entity_flags(id);
  
  if(user_flags & FL_ONGROUND)
  {
    just_surfed[id] = false;
    
    // Check if double duck is happening this frame
    //   https://kz-rush.ru/en/article/countjump-physics
    //   https://forums.alliedmods.net/showthread.php?p=619219
    if (!(user_flags & FL_DUCKING) && entity_get_int(id, EV_INT_bInDuck))
    {
      just_double_ducked[id] = true;
    }
  }
  
  return PLUGIN_CONTINUE;
}


public client_PostThink(id)
{
  if (!is_user_connected(id) || !enabled)
  {
    return PLUGIN_CONTINUE;
  }
  
  if (!is_user_alive(id) && debug_is_enabled && (user_enabled_speed[id] || is_user_admin(id)))
  {    
    new target = id;
    
    target = entity_get_int(id, EV_INT_iuser2);
    
    if (!is_user_alive(target))
    {
      return PLUGIN_CONTINUE;
    }
    
    new Float:velocity[3];
    new Float:speed;
    
    entity_get_vector(target, EV_VEC_velocity, velocity);
    speed = xs_vec_len_2d(velocity);
    
    show_speed(id, speed, maxspeed);
    
    return PLUGIN_CONTINUE;
  }
  
  new user_flags = get_entity_flags(id);
  
  if(user_flags & FL_ONGROUND)
  {
    just_surfed[id] = false;
    user_oldspeed[id] = 0.0;
    
    return PLUGIN_CONTINUE;
  }
  
  new Float:player_maxspeed = maxspeed;
  new bool:player_ducked    = just_double_ducked[id];
  new disable_acceleration  = noaccel_flags & NOACCEL_AIR;
  
  just_double_ducked[id] = false;
    
  new Float:velocity[3];
  new Float:speed;
  
  entity_get_vector(id, EV_VEC_velocity, velocity);
  speed = xs_vec_len_2d(velocity);
  
  if (player_ducked)
  {
    player_maxspeed   = duckspeed;
    user_oldspeed[id] = speed;
  }
  else if (entity_get_int(id, EV_INT_waterlevel))
  {
    just_surfed[id] = false;
    
    /**
    * 0 - Not in water
    * 1 - Waiding
    * 2 - Mostly submerged
    * 3 - Completely submerged
    */
    if (!(get_user_button(id) & IN_JUMP))
    {
      disable_acceleration = 0;
    }
    else
    {
      //~ client_print(id, print_chat, "waterlevel: %d", entity_get_int(id, EV_INT_waterlevel));
      disable_acceleration = (noaccel_flags & NOACCEL_SWIM);
      player_maxspeed      = swimspeed;
    }
  }
  else if (is_user_surfing(id) || just_surfed[id])
  {
    disable_acceleration = (noaccel_flags & NOACCEL_SURF);
    player_maxspeed      = surfspeed;
    just_surfed[id]      = true;
  }
  
  if (disable_acceleration && (user_oldspeed[id] > 0.0))
  {
    player_maxspeed = user_oldspeed[id];
  }
  
  if (speed <= player_maxspeed)
  {
    show_speed(id, speed, player_maxspeed, player_ducked)
    user_oldspeed[id] = speed;
    
    return PLUGIN_CONTINUE;
  }
  
  new Float:c;
  
  c = player_maxspeed / speed;
  speed *= c;
  user_oldspeed[id] = speed;
  
  velocity[0] *= c;
  velocity[1] *= c;
  
  entity_set_vector(id, EV_VEC_velocity, velocity);
  show_speed(id, speed, player_maxspeed, player_ducked)
  
  return PLUGIN_CONTINUE;
}

public is_user_surfing(id)
{
  new Float:origin[3];
  new Float:end[3];
  
  entity_get_vector(id, EV_VEC_origin, origin);
  xs_vec_copy(origin, end);
  
  end[2] -= 1.0;
  
  new hull = (get_entity_flags(id) & FL_DUCKING) ? HULL_HEAD : HULL_HUMAN;
  new Float:fraction;
  
  trace_hull(origin, hull, id, IGNORE_MONSTERS, end);
  traceresult(TR_Fraction, fraction);
  
  if (fraction == 1.0)
  {
    return 0;
  }
  
  new Float:normal[3];
  traceresult(TR_PlaneNormal, normal);
  
  new Float:cosine;
  new Float:vector_up[3] = {0.0, 0.0, 1.0};
  
  cosine = xs_vec_dot(normal, vector_up);
  //new Float:tilt = floatacos(cosine, degrees);
  
  //client_print(id, print_center, "[%3.3f°]", tilt);
  
  return (cosine <= 0.7)
}


show_speed(id, Float:speed, Float:player_maxspeed, bool:player_ducked = false)
{
  if (!debug_is_enabled || !user_enabled_speed[id])
  {
    return;
  }

  new Float:now = get_gametime();
  if (now < hud_time[id] && !player_ducked)
  {
    return;
  }
  
  new str[10];
  copy(str, sizeof str, (player_ducked) ? "[DUCKED]" : "");
  
  client_print(id, print_center, "%s %4.2f/%4.2f %s", str, speed, player_maxspeed, str)
  hud_time[id] = now + (player_ducked ? 0.3 : 0.1);
  
  return;
}

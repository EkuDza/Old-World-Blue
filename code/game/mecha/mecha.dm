#define MECHA_INT_FIRE 1
#define MECHA_INT_TEMP_CONTROL 2
#define MECHA_INT_SHORT_CIRCUIT 4
#define MECHA_INT_TANK_BREACH 8
#define MECHA_INT_CONTROL_LOST 16

#define MECHA_INT_ALL list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_SHORT_CIRCUIT,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST)

#define MELEE 1
#define RANGED 2


/obj/mecha
	name = "Mecha"
	desc = "Exosuit"
	icon = 'icons/mecha/mecha.dmi'
	density = 1 //Dense. To raise the heat.
	opacity = 1 ///opaque. Menacing.
	anchored = 1 //no pulling around.
	unacidable = 1 //and no deleting hoomans inside
	layer = MOB_LAYER //icon draw layer
	infra_luminosity = 15 //byond implementation is bugged.
	var/initial_icon = null //Mech type for resetting icon. Only used for reskinning kits (see custom items)
	var/can_move = 1
	var/step_in = 10 //make a step in step_in/10 sec.
	var/dir_in = 2//What direction will the mech face when entered/powered on? Defaults to South.
	var/step_energy_drain = 10
	var/health = 300 //health is health
	var/deflect_chance = 10 //chance to deflect the incoming projectiles, hits, or lesser the effect of ex_act.
	//the values in this list show how much damage will pass through, not how much will be absorbed.
	var/list/damage_absorption = list("brute"=0.8,"fire"=1.2,"bullet"=0.9,"laser"=1,"energy"=1,"bomb"=1)
	var/obj/item/weapon/cell/cell
	var/state = 0
	var/list/log = new
	var/last_message = 0
	var/add_req_access = 1
	var/maint_access = 1
	var/list/proc_res = list() //stores proc owners, like proc_res["functionname"] = owner reference
	var/datum/effect/effect/system/spark_spread/spark_system = new
	var/lights = 0
	var/lights_power = 6
	var/force = 0

	var/max_equip // Override for first seat
	var/list/seats = list()

	//inner atmos
	var/internal_tank_valve = ONE_ATMOSPHERE
	var/obj/machinery/portable_atmospherics/canister/internal_tank
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/atmospherics/portables_connector/connected_port = null

	var/max_temperature = 25000
	var/internal_damage_threshold = 50 //health percentage below which internal damage is possible
	var/internal_damage = 0 //contains bitflags

	var/list/internals_req_access = list(access_engine,access_robotics)//required access level to open cell compartment
	var/list/operation_req_access = list()//required access level for mecha operation

	var/datum/global_iterator/pr_int_temp_processor //normalizes internal air mixture temperature
	var/datum/global_iterator/pr_inertial_movement //controls intertial movement in spesss
	var/datum/global_iterator/pr_give_air //moves air from tank to cabin
	var/datum/global_iterator/pr_internal_damage //processes internal damage

	var/wreckage

	var/datum/events/events


/obj/mecha/drain_power(var/drain_check)

	if(drain_check)
		return 1

	if(!cell)
		return 0

	return cell.drain_power(drain_check)

/obj/mecha/New()
	..()
	events = new

	icon_state += "-open"
	add_airtank()
	add_cabin()
	setup_seats()
	spark_system.set_up(2, 0, src)
	spark_system.attach(src)
	add_cell()
	add_iterators()
	log_message("[src.name] created.")
	loc.Entered(src)
	mechas_list += src //global mech list
	return

/obj/mecha/Destroy()
	for(var/mob/M in src) //Let's just be ultra sure
		M.Move(loc)

	for(var/obj/cabin/C in seats)
		qdel(C)

	qdel(pr_int_temp_processor)
	pr_int_temp_processor = null

	qdel(pr_inertial_movement)
	pr_inertial_movement = null

	qdel(pr_give_air)
	pr_give_air = null

	qdel(pr_internal_damage)
	pr_internal_damage = null

	qdel(spark_system)
	spark_system = null

	qdel(cell)
	cell = null

	qdel(internal_tank)
	internal_tank = null

	mechas_list -= src //global mech list
	..()

/obj/mecha/proc/Death()
	if(loc)
		loc.Exited(src)

	if(prob(30))
		explosion(get_turf(loc), 0, 0, 1, 3)

	var/obj/effect/decal/mecha_wreckage/WR = null
	if(wreckage)
		WR = new wreckage(loc)

	for(var/obj/cabin/C in seats)
		C.Death(WR)

	if(WR)
		if(cell)
			WR.crowbar_salvage += cell
			cell.forceMove(WR)
			cell.charge = rand(0, cell.charge)
		if(internal_tank)
			WR.crowbar_salvage += internal_tank
			internal_tank.forceMove(WR)
	else
		if(cell)
			qdel(cell)
		if(internal_tank)
			qdel(internal_tank)

	qdel(src)


////////////////////////
////// Helpers /////////
////////////////////////

/obj/mecha/proc/removeVerb(verb_path)
	verbs -= verb_path

/obj/mecha/proc/addVerb(verb_path)
	verbs += verb_path

/obj/mecha/proc/add_airtank()
	internal_tank = new /obj/machinery/portable_atmospherics/canister/air(src)
	return internal_tank

/obj/mecha/proc/add_cell(var/obj/item/weapon/cell/C=null)
	if(C)
		C.forceMove(src)
		cell = C
		return
	cell = new(src)
	cell.name = "high-capacity power cell"
	cell.charge = 15000
	cell.maxcharge = 15000

/obj/mecha/proc/add_cabin()
	cabin_air = new
	cabin_air.temperature = T20C
	cabin_air.volume = 200
	cabin_air.adjust_multi(
		"oxygen",   O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature),
		"nitrogen", N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
	)
	return cabin_air

/obj/mecha/proc/setup_seats()
	for(var/obj/cabin/C in seats)
		qdel(C)
	seats += new/obj/cabin/pilot(src, max_equip)
	return 1

/obj/mecha/proc/add_iterators()
	pr_int_temp_processor = new /datum/global_iterator/mecha_preserve_temp(list(src))
	pr_inertial_movement = new /datum/global_iterator/mecha_intertial_movement(null,0)
	pr_give_air = new /datum/global_iterator/mecha_tank_give_air(list(src))
	pr_internal_damage = new /datum/global_iterator/mecha_internal_damage(list(src),0)

/obj/mecha/proc/do_after(delay as num)
	sleep(delay)
	if(src)
		return 1
	return 0

/obj/mecha/proc/enter_after(delay as num, var/mob/user as mob, var/numticks = 5)
	var/delayfraction = delay/numticks

	var/turf/T = user.loc

	for(var/i = 0, i<numticks, i++)
		sleep(delayfraction)
		if(!src || !user || !user.canmove || !(user.loc == T))
			return 0

	return 1



/obj/mecha/proc/check_for_support()
	if(
		locate(/obj/structure/grille, range(1, src))  || \
		locate(/obj/structure/lattice, range(1, src)) || \
		locate(/turf/simulated, range(1, src)) || \
		locate(/turf/unsimulated, range(1, src))
	)
		return 1
	else
		return 0

/obj/mecha/examine(mob/user)
	. = ..()
	var/integrity = health/initial(health)*100
	switch(integrity)
		if(85 to 100)
			user << "It's fully intact."
		if(65 to 85)
			user << "It's slightly damaged."
		if(45 to 65)
			user << "It's badly damaged."
		if(25 to 45)
			user << "It's heavily damaged."
		else
			user << "It's falling apart."
	for(var/obj/cabin/C in seats)
		C.examine(user)
	return


/obj/mecha/see_emote(mob/living/M, text)
	for(var/obj/cabin/C in seats)
		C.see_emote(M, text)
	..()

////////////////////////////
///// Action processing ////
////////////////////////////

/obj/mecha/proc/can_operate(atom/target,mob/user)
	if(state)
		occupant_message("<font color='red'>Maintenance protocols in effect</font>")
		return 0
	if(!get_charge()) return 0
	var/dir_to_target = get_dir(src,target)
	if(dir_to_target && !(dir_to_target & src.dir))//wrong direction
		return
	return 1

/obj/mecha/proc/melee_action(atom/target)
	return

/obj/mecha/proc/range_action(atom/target)
	return


//////////////////////////////////
////////  Movement procs  ////////
//////////////////////////////////

/obj/mecha/Move()
	. = ..()
	if(.)
		events.fireEvent("onMove",get_turf(src))
	return

/obj/mecha/relaymove(mob/user,direction)
	if(connected_port)
		if(world.time - last_message > 20)
			src.occupant_message("Unable to move while connected to the air system port")
			last_message = world.time
		return 0
	if(state)
		occupant_message("<font color='red'>Maintenance protocols in effect</font>")
		return
	return domove(direction)

/obj/mecha/proc/domove(direction)
	return call((proc_res["dyndomove"]||src), "dyndomove")(direction)

/obj/mecha/proc/dyndomove(direction)
	if(!can_move)
		return 0
	if(src.pr_inertial_movement.active())
		return 0
	if(!has_charge(step_energy_drain))
		return 0
	var/move_result = 0
	if(hasInternalDamage(MECHA_INT_CONTROL_LOST))
		move_result = mechsteprand()
	else if(src.dir!=direction)
		move_result = mechturn(direction)
	else
		move_result = mechstep(direction)
	if(move_result)
		can_move = 0
		use_power(step_energy_drain)
		if(istype(src.loc, /turf/space))
			if(!src.check_for_support())
				src.pr_inertial_movement.start(list(src,direction))
				src.log_message("Movement control lost. Inertial movement started.")
		if(do_after(step_in))
			can_move = 1
		return 1
	return 0

/obj/mecha/proc/mechturn(direction)
	set_dir(direction)
	playsound(src,'sound/mecha/Mech_Rotation.wav',40,1)
	return 1

/obj/mecha/proc/mechstep(direction)
	var/result = step(src,direction)
	if(result)
		playsound(src,'sound/mecha/Mech_Step.wav',100,1)
	return result


/obj/mecha/proc/mechsteprand()
	var/result = step_rand(src)
	if(result)
		playsound(src,'sound/mecha/Mech_Step.wav',100,1)
	return result

/obj/mecha/Bump(var/atom/obstacle)
	if(istype(obstacle, /obj))
		var/obj/O = obstacle
		if(istype(O, /obj/effect/portal)) //derpfix
			src.anchored = 0
			O.Crossed(src)
			spawn(0)//countering portal teleport spawn(0), hurr
				src.anchored = 1
		else if(!O.anchored)
			step(obstacle,src.dir)
		else //I have no idea why I disabled this
			obstacle.Bumped(src)
	else if(istype(obstacle, /mob))
		step(obstacle,src.dir)
	else
		obstacle.Bumped(src)
	return

///////////////////////////////////
////////  Internal damage  ////////
///////////////////////////////////

/obj/mecha/proc/check_for_internal_damage(var/list/possible_int_damage,var/ignore_threshold=null)
	if(!islist(possible_int_damage) || isemptylist(possible_int_damage)) return
	if(prob(20))
		if(ignore_threshold || src.health*100/initial(src.health)<src.internal_damage_threshold)
			for(var/T in possible_int_damage)
				if(internal_damage & T)
					possible_int_damage -= T
			var/int_dam_flag = safepick(possible_int_damage)
			if(int_dam_flag)
				setInternalDamage(int_dam_flag)
/*
	if(prob(5))
		if(ignore_threshold || src.health*100/initial(src.health)<src.internal_damage_threshold)
			var/obj/item/mecha_parts/mecha_equipment/destr = safepick(equipment)
			if(destr)
				destr.destroy()
*/
	return

/obj/mecha/proc/hasInternalDamage(int_dam_flag=null)
	return int_dam_flag ? internal_damage&int_dam_flag : internal_damage


/obj/mecha/proc/setInternalDamage(int_dam_flag)
	if(!pr_internal_damage) return

	internal_damage |= int_dam_flag
	pr_internal_damage.start()
	log_append_to_last("Internal damage of type [int_dam_flag].",1)
	return

/obj/mecha/proc/clearInternalDamage(int_dam_flag)
	internal_damage &= ~int_dam_flag
	switch(int_dam_flag)
		if(MECHA_INT_TEMP_CONTROL)
			occupant_message("<font color='blue'><b>Life support system reactivated.</b></font>")
			pr_int_temp_processor.start()
		if(MECHA_INT_FIRE)
			occupant_message("<font color='blue'><b>Internal fire extinquished.</b></font>")
		if(MECHA_INT_TANK_BREACH)
			occupant_message("<font color='blue'><b>Damaged internal tank has been sealed.</b></font>")
	return


////////////////////////////////////////
////////  Health related procs  ////////
////////////////////////////////////////

/obj/mecha/proc/take_damage(amount, type="brute")
	if(amount)
		var/damage = absorbDamage(amount,type)
		health -= damage
		update_health()
		log_append_to_last("Took [damage] points of damage. Damage type: \"[type]\".",1)
	return

/obj/mecha/proc/absorbDamage(damage,damage_type)
	return call((proc_res["dynabsorbdamage"]||src), "dynabsorbdamage")(damage,damage_type)

/obj/mecha/proc/dynabsorbdamage(damage,damage_type)
	return damage*(listgetindex(damage_absorption,damage_type) || 1)

/obj/mecha/airlock_crush(var/crush_damage)
	..()
	take_damage(crush_damage)
	check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return 1

/obj/mecha/proc/update_health()
	if(src.health > 0)
		src.spark_system.start()
	else
		Death(src)
	return

/obj/mecha/attack_hand(mob/user as mob)
	src.log_message("Attack by hand/paw. Attacker - [user].",1)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.can_shred())
			if(!prob(src.deflect_chance))
				src.take_damage(15)
				src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
				playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
				user << "\red You slash at the armored suit!"
				visible_message("\red The [user] slashes at [src.name]'s armor!")
			else
				src.log_append_to_last("Armor saved.")
				playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
				user << "\green Your claws had no effect!"
				src.occupant_message("\blue The [user]'s claws are stopped by the armor.")
				visible_message("\blue The [user] rebounds off [src.name]'s armor!")
		else
			user.visible_message(
				"<font color='red'><b>[user] hits [src.name]. Nothing happens</b></font>",
				"<font color='red'><b>You hit [src.name] with no visible effect.</b></font>"
			)
			src.log_append_to_last("Armor saved.")
		return
	else if ((HULK in user.mutations) && !prob(src.deflect_chance))
		src.take_damage(15)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		user.visible_message(
			"<font color='red'><b>[user] hits [src.name], doing some damage.</b></font>",
			"<font color='red'><b>You hit [src.name] with all your might. The metal creaks and bends.</b></font>"
		)
	else
		user.visible_message(
			"<font color='red'><b>[user] hits [src.name]. Nothing happens</b></font>",
			"<font color='red'><b>You hit [src.name] with no visible effect.</b></font>"
		)
		src.log_append_to_last("Armor saved.")
	return

/obj/mecha/hitby(atom/movable/A as mob|obj) //wrapper
	..()
	src.log_message("Hit by [A].",1)
	call((proc_res["dynhitby"]||src), "dynhitby")(A)
	return

/obj/mecha/proc/dynhitby(atom/movable/A)
	if(istype(A, /obj/item/mecha_parts/mecha_tracking))
		A.forceMove(src)
		src.visible_message("The [A] fastens firmly to [src].")
		return
	if(prob(src.deflect_chance) || istype(A, /mob))
		src.occupant_message("\blue The [A] bounces off the armor.")
		src.visible_message("The [A] bounces off the [src.name] armor")
		src.log_append_to_last("Armor saved.")
		if(istype(A, /mob/living))
			var/mob/living/M = A
			M.take_organ_damage(10)
	else if(istype(A, /obj))
		var/obj/O = A
		if(O.throwforce)
			src.take_damage(O.throwforce)
			src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return


/obj/mecha/bullet_act(var/obj/item/projectile/Proj) //wrapper
	src.log_message("Hit by projectile. Type: [Proj.name]([Proj.check_armour]).",1)
	call((proc_res["dynbulletdamage"]||src), "dynbulletdamage")(Proj) //calls equipment
	..()
	return

/obj/mecha/proc/dynbulletdamage(var/obj/item/projectile/Proj)
	if(prob(src.deflect_chance))
		src.occupant_message("\blue The armor deflects incoming projectile.")
		src.visible_message("The [src.name] armor deflects the projectile")
		src.log_append_to_last("Armor saved.")
		return

	if(Proj.damage_type == HALLOSS)
		use_power(Proj.agony * 5)

	if(!(Proj.nodamage))
		var/ignore_threshold
		if(istype(Proj, /obj/item/projectile/beam/pulse))
			ignore_threshold = 1
		src.take_damage(Proj.damage, Proj.check_armour)
		if(prob(25)) spark_system.start()
		src.check_for_internal_damage(MECHA_INT_ALL,ignore_threshold)

		//AP projectiles have a chance to cause additional damage
		if(Proj.penetrating)
			var/distance = get_dist(Proj.starting, get_turf(loc))
			var/hit_occupant = 1 //only allow the occupant to be hit once
			for(var/i in 1 to min(Proj.penetrating, round(Proj.damage/15)))
				if(hit_occupant && prob(20))
					var/obj/cabin/C = pick(seats)
					if(C.occupant)
						Proj.attack_mob(C.occupant, distance)
					hit_occupant = 0
				else
					src.check_for_internal_damage(MECHA_INT_ALL, 1)

				Proj.penetrating--

				if(prob(15))
					break //give a chance to exit early

	Proj.on_hit(src)
	return

/obj/mecha/ex_act(severity)
	src.log_message("Affected by explosion of severity: [severity].",1)
	if(prob(src.deflect_chance))
		severity++
		src.log_append_to_last("Armor saved, changing severity to [severity].")
	switch(severity)
		if(1.0)
			Death(src)
		if(2.0)
			if (prob(30))
				Death(src)
			else
				src.take_damage(initial(src.health)/2)
				src.check_for_internal_damage(MECHA_INT_ALL,1)
		if(3.0)
			if (prob(5))
				Death(src)
			else
				src.take_damage(initial(src.health)/5)
				src.check_for_internal_damage(MECHA_INT_ALL,1)
	return



//TODO
/obj/mecha/meteorhit()
	return ex_act(rand(1,3))//should do for now

/obj/mecha/emp_act(severity)
	if(get_charge())
		use_power((cell.charge/2)/severity)
		take_damage(50 / severity,"energy")
	src.log_message("EMP detected",1)
	check_for_internal_damage(list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_CONTROL_LOST,MECHA_INT_SHORT_CIRCUIT),1)
	return

/obj/mecha/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	if(exposed_temperature>src.max_temperature)
		src.log_message("Exposed to dangerous temperature.",1)
		src.take_damage(5,"fire")
		src.check_for_internal_damage(list(MECHA_INT_FIRE, MECHA_INT_TEMP_CONTROL))
	return

/obj/mecha/proc/dynattackby(obj/item/weapon/W as obj, mob/user as mob)
	src.log_message("Attacked by [W]. Attacker - [user]")
	if(prob(src.deflect_chance))
		src.visible_message("\red \The [W] bounces off [src.name].")
		src.log_append_to_last("Armor saved.")
	else
		src.occupant_message("<font color='red'><b>[user] hits [src] with [W].</b></font>")
		user.visible_message(
			"<font color='red'><b>[user] hits [src] with [W].</b></font>",
			"<font color='red'><b>You hit [src] with [W].</b></font>"
		)
		src.take_damage(W.force,W.damtype)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return

/obj/mecha/proc/try_fix_control()
	usr << sound('sound/mecha/UI_SCI-FI_Compute_01_Wet_stereo.wav',channel=4, volume=100);
	var/T = src.loc
	if(do_after(100))
		if(T == src.loc)
			src.clearInternalDamage(MECHA_INT_CONTROL_LOST)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.wav',channel=4, volume=100);
			occupant_message("<font color='blue'>Recalibration successful.</font>")
			src.log_message("Recalibration of coordination system finished with 0 errors.")
		else
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.wav',channel=4, volume=100);
			occupant_message("<font color='red'>Recalibration failed.</font>")
			src.log_message("Recalibration of coordination system failed with 1 error.",1)


//////////////////////
////// AttackBy //////
//////////////////////

// For preloaded mechas etc.
/obj/mecha/proc/attach(var/obj/item/mecha_parts/mecha_equipment/E)
	var/obj/cabin/C = seats[1]
	C.attach(E)

/obj/mecha/attackby(obj/item/weapon/W as obj, mob/user as mob)
	if(istype(W, /obj/item/mecha_parts/mecha_equipment))
		var/obj/cabin/C = input("Select place for attach", "Pilot") as null|anything in seats
		if(!C || !Adjacent(user)) return
		if(C.can_attach(W, user))
			C.attach(W, user)
		else
			user << "You can't attach [W] to [src]"
		return
	if(istype(W, /obj/item/weapon/card/id)||istype(W, /obj/item/device/pda))
		if(add_req_access || maint_access)
			if(internals_access_allowed(usr))
				var/obj/item/weapon/card/id/id_card
				if(istype(W, /obj/item/weapon/card/id))
					id_card = W
				else
					var/obj/item/device/pda/pda = W
					id_card = pda.id
				output_maintenance_dialog(id_card, user)
				return
			else
				user << "\red Invalid ID: Access denied."
		else
			user << "\red Maintenance protocols disabled by operator."
	else if(istype(W, /obj/item/weapon/wrench))
		if(state==1)
			state = 2
			user << "You undo the securing bolts."
		else if(state==2)
			state = 1
			user << "You tighten the securing bolts."
		return
	else if(istype(W, /obj/item/weapon/crowbar))
		if(state==2)
			state = 3
			user << "You open the hatch to the power unit"
		else if(state==3)
			state=2
			user << "You close the hatch to the power unit"
		return
	else if(istype(W, /obj/item/stack/cable_coil))
		if(state == 3 && hasInternalDamage(MECHA_INT_SHORT_CIRCUIT))
			var/obj/item/stack/cable_coil/CC = W
			if(CC.use(2))
				clearInternalDamage(MECHA_INT_SHORT_CIRCUIT)
				user << "You replace the fused wires."
			else
				user << "There's not enough wire to finish the task."
		return
	else if(istype(W, /obj/item/weapon/screwdriver))
		if(hasInternalDamage(MECHA_INT_TEMP_CONTROL))
			clearInternalDamage(MECHA_INT_TEMP_CONTROL)
			user << "You repair the damaged temperature controller."
		else if(state==3 && src.cell)
			src.cell.forceMove(src.loc)
			src.cell = null
			state = 4
			user << "You unscrew and pry out the powercell."
			src.log_message("Powercell removed")
		else if(state==4 && src.cell)
			state=3
			user << "You screw the cell in place"
		return
/*
	else if(istype(W, /obj/item/device/multitool))
		if(state>=3 && src.occupant)
			user << "You attempt to eject the pilot using the maintenance controls."
			if(src.occupant.stat)
				src.go_out()
				src.log_message("[src.occupant] was ejected using the maintenance controls.")
			else
				user << "<span class='warning'>Your attempt is rejected.</span>"
				src.occupant_message("<span class='warning'>An attempt to eject you was made using the maintenance controls.</span>")
				src.log_message("Eject attempt made using maintenance controls - rejected.")
		return
*/
	else if(istype(W, /obj/item/weapon/cell))
		if(state==4)
			if(!src.cell)
				user << "You install the powercell"
				user.drop_item()
				W.forceMove(src)
				src.cell = W
				src.log_message("Powercell installed")
			else
				user << "There's already a powercell installed."
		return

	else if(istype(W, /obj/item/weapon/weldingtool) && user.a_intent != I_HURT)
		var/obj/item/weapon/weldingtool/WT = W
		if (WT.remove_fuel(0,user))
			if (hasInternalDamage(MECHA_INT_TANK_BREACH))
				clearInternalDamage(MECHA_INT_TANK_BREACH)
				user << "\blue You repair the damaged gas tank."
		else
			return
		if(src.health<initial(src.health))
			user << "\blue You repair some damage to [src.name]."
			src.health += min(10, initial(src.health)-src.health)
		else
			user << "The [src.name] is at full integrity"
		return

	else if(istype(W, /obj/item/mecha_parts/mecha_tracking))
		user.drop_from_inventory(W)
		W.forceMove(src)
		user.visible_message("[user] attaches [W] to [src].", "You attach [W] to [src]")
		return

	else
		call((proc_res["dynattackby"]||src), "dynattackby")(W,user)
/*
		src.log_message("Attacked by [W]. Attacker - [user]")
		if(prob(src.deflect_chance))
			user << "\red The [W] bounces off [src.name] armor."
			src.log_append_to_last("Armor saved.")
		else
			src.occupant_message("<font color='red'><b>[user] hits [src] with [W].</b></font>")
			user.visible_message("<font color='red'><b>[user] hits [src] with [W].</b></font>", "<font color='red'><b>You hit [src] with [W].</b></font>")
			src.take_damage(W.force,W.damtype)
			src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
*/
	return


/*
/obj/mecha/attack_ai(var/mob/living/silicon/ai/user as mob)
	if(!istype(user, /mob/living/silicon/ai))
		return
	var/output = {"
		<b>Assume direct control over [src]?</b>
		<a href='?src=\ref[src];ai_take_control=\ref[user];duration=3000'>Yes</a><br>
	"}
	user << browse(output, "window=mecha_attack_ai")
	return
*/


/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/mecah/proc/get_turf_air()
	var/turf/T = get_turf(src)
	if(T)
	return T.return_air()


/obj/mecha/proc/connect(obj/machinery/atmospherics/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port || !new_port || new_port.connected_device)
		return 0

	//Make sure are close enough for a valid connection
	if(new_port.loc != src.loc)
		return 0

	for(var/obj/cabin/pilot/C in seats)
		C.verbs -= /obj/cabin/proc/connect_to_port
		C.verbs += /obj/cabin/proc/disconnect_from_port

	//Perform the connection
	connected_port = new_port
	connected_port.connected_device = src

	//Actually enforce the air sharing
	var/datum/pipe_network/network = connected_port.return_network(src)
	if(network && !(internal_tank.return_air() in network.gases))
		network.gases += internal_tank.return_air()
		network.update = 1
	log_message("Connected to gas port.")
	return 1

/obj/mecha/proc/disconnect(var/obj/cabin/requester)
	if(!connected_port)
		requester.occupant_message("\red [name] is not connected to the port at the moment.")
		return 0

	var/datum/pipe_network/network = connected_port.return_network(src)
	if(network)
		network.gases -= internal_tank.return_air()

	connected_port.connected_device = null
	connected_port = null

	for(var/obj/cabin/pilot/C in seats)
		C.verbs -= /obj/cabin/proc/disconnect_from_port
		C.verbs += /obj/cabin/proc/connect_to_port

	src.log_message("Disconnected from gas port.")
	requester.occupant_message("\blue [name] disconnects from the port.")
	return 1

/////////////////////////
////////  Procs  ////////
/////////////////////////

/obj/mecha/proc/toggle_lights()
	lights = !lights
	if(lights)	set_light(light_range + lights_power)
	else		set_light(light_range - lights_power)
	src.occupant_message("Toggled lights [lights?"on":"off"].")
	log_message("Toggled lights [lights?"on":"off"].")
	return

/////////////////////////
////////  Verbs  ////////
/////////////////////////

/obj/mecha/verb/move_inside()
	set category = "Object"
	set name = "Enter Exosuit"
	set src in oview(1)

	if (usr.stat || !ishuman(usr))
		return
	var/mob/living/carbon/human/H = usr
	if(H.handcuffed)
		usr << "\red Kinda hard to climb in while handcuffed don't you think?"
		return

	for(var/mob/living/carbon/slime/M in range(1,usr))
		if(M.Victim == usr)
			usr << "You're too busy getting your life sucked out of you."
			return

	var/obj/cabin/C = input("Select place for enter", "Cabin") as null|anything in seats
	if(!C) return
	src.log_message("[H] tries to move in [C].")
	C.move_inside(H)

/////////////////////////
////// Access stuff /////
/////////////////////////

/obj/mecha/proc/internals_access_allowed(mob/living/carbon/human/H)
	for(var/atom/ID in list(H.get_active_hand(), H.wear_id, H.belt))
		if(src.check_access(ID,src.internals_req_access))
			return 1
	return 0

/obj/mecha/check_access(obj/item/weapon/card/id/I, list/access_list)
	if(!istype(access_list))
		return 1
	if(!access_list.len) //no requirements
		return 1
	if(istype(I, /obj/item/device/pda))
		var/obj/item/device/pda/pda = I
		I = pda.id
	if(!istype(I) || !I.access) //not ID or no access
		return 0
	if(access_list==src.operation_req_access)
		for(var/req in access_list)
			if(!(req in I.access)) //doesn't have this access
				return 0
	else if(access_list==src.internals_req_access)
		for(var/req in access_list)
			if(req in I.access)
				return 1
	return 1


////////////////////////////////////
///// Rendering stats window ///////
////////////////////////////////////

/obj/mecha/proc/report_internal_damage()
	var/output = null
	var/list/dam_reports = list(
		"[MECHA_INT_FIRE]" = "<font color='red'><b>INTERNAL FIRE</b></font>",
		"[MECHA_INT_TEMP_CONTROL]" = "<font color='red'><b>LIFE SUPPORT SYSTEM MALFUNCTION</b></font>",
		"[MECHA_INT_TANK_BREACH]" = "<font color='red'><b>GAS TANK BREACH</b></font>",
		"[MECHA_INT_CONTROL_LOST]" = "<font color='red'><b>COORDINATION SYSTEM CALIBRATION FAILURE</b></font> - \
									<a href='?src=\ref[src];repair_int_control_lost=1'>Recalibrate</a>",
		"[MECHA_INT_SHORT_CIRCUIT]" = "<font color='red'><b>SHORT CIRCUIT</b></font>"
	)
	for(var/tflag in dam_reports)
		var/intdamflag = text2num(tflag)
		if(hasInternalDamage(intdamflag))
			output += dam_reports[tflag]
			output += "<br />"
	return output


/obj/mecha/proc/get_stats_part()
	var/integrity = health/initial(health)*100
	var/cell_charge = get_charge()
	var/output = {"
		[report_internal_damage()]
		[integrity<30?"<font color='red'><b>DAMAGE LEVEL CRITICAL</b></font><br>":null]
		<b>Integrity: </b> [integrity]%<br>
		<b>Powercell charge: </b>[isnull(cell_charge)?"No powercell installed":"[cell.percent()]%"]<br>
		<b>Lights: </b>[lights?"on":"off"]<br>
	"}
	return output


/obj/mecha/proc/get_log_html()
	var/output = "<html><head><title>[src.name] Log</title></head><body style='font: 13px 'Courier', monospace;'>"
	for(var/list/entry in log)
		output += {"
			<div style='font-weight: bold;'>[time2text(entry["time"],"DDD MMM DD hh:mm:ss")] [game_year]</div>
			<div style='margin-left:15px; margin-bottom:10px;'>[entry["message"]]</div>
		"}
	output += "</body></html>"
	return output


/obj/mecha/proc/output_access_dialog(obj/item/weapon/card/id/id_card, mob/user)
	if(!id_card || !user) return
	var/output = {"
		<html>
		<head><style>
			h1 {font-size:15px;margin-bottom:4px;}
			body {color: #00ff00; background: #000000; font-family:"Courier New", Courier, monospace; font-size: 12px;}
			a {color:#0f0;}
		</style></head>
		<body>
		<h1>Following keycodes are present in this system:</h1>
	"}
	for(var/a in req_access)
		output += "[get_access_desc(a)] - <a href='?src=\ref[src];del_req_access=[a];user=\ref[user];id_card=\ref[id_card]'>Delete</a><br>"
	output += "<hr><h1>Following keycodes were detected on portable device:</h1>"
	for(var/a in id_card.access)
		if(a in operation_req_access) continue
		var/a_name = get_access_desc(a)
		if(!a_name) continue //there's some strange access without a name
		output += "[a_name] - <a href='?src=\ref[src];add_req_access=[a];user=\ref[user];id_card=\ref[id_card]'>Add</a><br>"
	output += {"
		<hr><a href='?src=\ref[src];finish_req_access=1;user=\ref[user]'>Finish</a>
		<font color='red'>(Warning! The ID upload panel will be locked.
			It can be unlocked only through Exosuit Interface.)</font>"}
	output += "</body></html>"
	user << browse(output, "window=exosuit_add_access")
	onclose(user, "exosuit_add_access")
	return

/obj/mecha/proc/output_maintenance_dialog(obj/item/weapon/card/id/id_card,mob/user)
	if(!id_card || !user) return

	var/maint_options = "<a href='?src=\ref[src];set_internal_tank_valve=1;user=\ref[user]'>Set Cabin Air Pressure</a>"
	if (locate(/obj/item/mecha_parts/mecha_equipment/tool/passenger) in contents)
		maint_options += "<a href='?src=\ref[src];remove_passenger=1;user=\ref[user]'>Remove Passenger</a>"

	var/output = {"
		<html><head>
		<style>
		body {color: #00ff00; background: #000000; font-family:"Courier New", Courier, monospace; font-size: 12px;}
		a {padding:2px 5px; background:#32CD32;color:#000;display:block;margin:2px;text-align:center;text-decoration:none;}
		</style>
		</head><body>
		[add_req_access?"<a href='?src=\ref[src];req_access=1;id_card=\ref[id_card];user=\ref[user]'>Edit operation keycodes</a>":null]
		[maint_access?"<a href='?src=\ref[src];maint_access=1;id_card=\ref[id_card];user=\ref[user]'>Initiate maintenance protocol</a>":null]
		[(state>0) ? maint_options : ""]
		</body></html>
	"}
	user << browse(output, "window=exosuit_maint_console")
	onclose(user, "exosuit_maint_console")
	return


////////////////////////////////
/////// Messages and Log ///////
////////////////////////////////

/obj/mecha/proc/occupant_message(message as text)
	message = "\icon[src] [message]"
	for(var/obj/cabin/C in seats)
		C.occupant_message(message)

/obj/mecha/proc/log_message(message as text,red=null)
	log.len++
	log[log.len] = list("time"=world.timeofday,"message"=red?"<font color='red'>[message]</font>":message)
	return log.len

/obj/mecha/proc/log_append_to_last(message as text,red=null)
	var/list/last_entry = src.log[src.log.len]
	last_entry["message"] += "<br>[red?"<font color='red'>[message]</font>":message]"
	return


/////////////////
///// Topic /////
/////////////////

/obj/mecha/Topic(href, href_list)
	..()
	if(href_list["close"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		return
	if(usr.stat > 0)
		return
	var/datum/topic_input/filter = new (href,href_list)
	if(!in_range(src, usr))	return

	if(href_list["req_access"] && add_req_access)
		output_access_dialog(filter.getObj("id_card"),filter.getMob("user"))
		return
	if(href_list["maint_access"] && maint_access)
		var/mob/user = filter.getMob("user")
		if(user)
			if(state==0)
				state = 1
				user << "The securing bolts are now exposed."
			else if(state==1)
				state = 0
				user << "The securing bolts are now hidden."
			output_maintenance_dialog(filter.getObj("id_card"),user)
		return
	if(href_list["set_internal_tank_valve"] && state >=1)
		var/mob/user = filter.getMob("user")
		if(user)
			var/new_pressure = input(user,"Input new output pressure","Pressure setting",internal_tank_valve) as num
			if(new_pressure)
				internal_tank_valve = new_pressure
				user << "The internal pressure valve has been set to [internal_tank_valve]kPa."
/*
	if(href_list["remove_passenger"] && state >= 1)
		var/mob/user = filter.getMob("user")
		var/list/passengers = list()
		for (var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P in contents)
			if (P.occupant)
				passengers["[P.occupant]"] = P

		if (!passengers)
			user << "\red There are no passengers to remove."
			return

		var/pname = input(user, "Choose a passenger to forcibly remove.", "Forcibly Remove Passenger") as null|anything in passengers

		if (!pname)
			return

		var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = passengers[pname]
		var/mob/occupant = P.occupant

		user.visible_message("\red [user] begins opening the hatch on \the [P]...", "\red You begin opening the hatch on \the [P]...")
		if (!do_after(user, 40, needhand=0))
			return

		user.visible_message("\red [user] opens the hatch on \the [P] and removes [occupant]!", "\red You open the hatch on \the [P] and remove [occupant]!")
		P.go_out()
		P.log_message("[occupant] was removed.")
		return
*/
		if(href_list["add_req_access"] && add_req_access && filter.getObj("id_card"))
		operation_req_access += filter.getNum("add_req_access")
		output_access_dialog(filter.getObj("id_card"),filter.getMob("user"))
		return
	if(href_list["del_req_access"] && add_req_access && filter.getObj("id_card"))
		operation_req_access -= filter.getNum("del_req_access")
		output_access_dialog(filter.getObj("id_card"),filter.getMob("user"))
		return
	if(href_list["finish_req_access"])
		add_req_access = 0
		var/mob/user = filter.getMob("user")
		user << browse(null,"window=exosuit_add_access")
		user << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.wav',channel=4, volume=100);
		return
	//debug
	/*
	if(href_list["debug"])
		if(href_list["set_i_dam"])
			setInternalDamage(filter.getNum("set_i_dam"))
		if(href_list["clear_i_dam"])
			clearInternalDamage(filter.getNum("clear_i_dam"))
		return
	*/



/*
	if (href_list["ai_take_control"])
		var/mob/living/silicon/ai/AI = locate(href_list["ai_take_control"])
		var/duration = text2num(href_list["duration"])
		var/mob/living/silicon/ai/O = new /mob/living/silicon/ai(src)
		var/cur_occupant = src.occupant
		O.invisibility = 0
		O.canmove = 1
		O.name = AI.name
		O.real_name = AI.real_name
		O.anchored = 1
		O.aiRestorePowerRoutine = 0
		O.control_disabled = 1 // Can't control things remotely if you're stuck in a card!
		O.laws = AI.laws
		O.stat = AI.stat
		O.oxyloss = AI.getOxyLoss()
		O.fireloss = AI.getFireLoss()
		O.bruteloss = AI.getBruteLoss()
		O.toxloss = AI.toxloss
		O.updatehealth()
		src.occupant = O
		if(AI.mind)
			AI.mind.transfer_to(O)
		AI.name = "Inactive AI"
		AI.real_name = "Inactive AI"
		AI.icon_state = "ai-empty"
		spawn(duration)
			AI.name = O.name
			AI.real_name = O.real_name
			if(O.mind)
				O.mind.transfer_to(AI)
			AI.control_disabled = 0
			AI.laws = O.laws
			AI.oxyloss = O.getOxyLoss()
			AI.fireloss = O.getFireLoss()
			AI.bruteloss = O.getBruteLoss()
			AI.toxloss = O.toxloss
			AI.updatehealth()
			qdel(O)
			if (!AI.stat)
				AI.icon_state = "ai"
			else
				AI.icon_state = "ai-crash"
			src.occupant = cur_occupant
*/
	return

///////////////////////
///// Power stuff /////
///////////////////////

/obj/mecha/proc/has_charge(amount)
	return (get_charge()>=amount)

/obj/mecha/proc/get_charge()
	return call((proc_res["dyngetcharge"]||src), "dyngetcharge")()

/obj/mecha/proc/dyngetcharge()//returns null if no powercell, else returns cell.charge
	if(!src.cell) return
	return max(0, src.cell.charge)

/obj/mecha/proc/use_power(amount)
	return call((proc_res["dynusepower"]||src), "dynusepower")(amount)

/obj/mecha/proc/dynusepower(amount)
	if(get_charge())
		cell.use(amount)
		return 1
	return 0

/obj/mecha/proc/give_power(amount)
	if(!isnull(get_charge()))
		cell.give(amount)
		return 1
	return 0

/obj/mecha/proc/reset_icon()
	if (initial_icon)
		icon_state = initial_icon
	else
		icon_state = initial(icon_state)
	return icon_state

/obj/mecha/attack_generic(var/mob/user, var/damage, var/attack_message)

	if(!damage)
		return 0

	src.log_message("Attacked. Attacker - [user].",1)

	user.do_attack_animation(src)
	if(!prob(src.deflect_chance))
		src.take_damage(damage)
		src.check_for_internal_damage(list(MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
		visible_message("\red <B>[user]</B> [attack_message] [src]!")
		user.attack_log += text("\[[time_stamp()]\] <font color='red'>attacked [src.name]</font>")
	else
		src.log_append_to_last("Armor saved.")
		playsound(src.loc, 'sound/weapons/slash.ogg', 50, 1, -1)
		src.occupant_message("\blue The [user]'s attack is stopped by the armor.")
		visible_message("\blue The [user] rebounds off [src.name]'s armor!")
		user.attack_log += text("\[[time_stamp()]\] <font color='red'>attacked [src.name]</font>")
	return 1


//////////////////////////////////////////
////////  Mecha global iterators  ////////
//////////////////////////////////////////


/datum/global_iterator/mecha_preserve_temp  //normalizing cabin air temperature to 20 degrees celsium
	delay = 20

	process(var/obj/mecha/mecha)
		if(mecha.cabin_air && mecha.cabin_air.volume > 0)
			var/delta = mecha.cabin_air.temperature - T20C
			mecha.cabin_air.temperature -= max(-10, min(10, round(delta/4,0.1)))
		return

/datum/global_iterator/mecha_tank_give_air
	delay = 15

	process(var/obj/mecha/mecha)
		if(mecha.internal_tank)
			var/datum/gas_mixture/tank_air = mecha.internal_tank.return_air()
			var/datum/gas_mixture/cabin_air = mecha.cabin_air

			var/release_pressure = mecha.internal_tank_valve
			var/cabin_pressure = cabin_air.return_pressure()
			var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure)/2)
			var/transfer_moles = 0
			if(pressure_delta > 0) //cabin pressure lower than release pressure
				if(tank_air.temperature > 0)
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
					cabin_air.merge(removed)
			else if(pressure_delta < 0) //cabin pressure higher than release pressure
				var/datum/gas_mixture/t_air = mecha.get_turf_air()
				pressure_delta = cabin_pressure - release_pressure
				if(t_air)
					pressure_delta = min(cabin_pressure - t_air.return_pressure(), pressure_delta)
				if(pressure_delta > 0) //if location pressure is lower than cabin pressure
					transfer_moles = pressure_delta*cabin_air.volume/(cabin_air.temperature * R_IDEAL_GAS_EQUATION)
					var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
					if(t_air)
						t_air.merge(removed)
					else //just delete the cabin gas, we're in space or some shit
						qdel(removed)
		else
			return stop()
		return

/datum/global_iterator/mecha_intertial_movement //inertial movement in space
	delay = 7

	process(var/obj/mecha/mecha as obj,direction)
		if(direction)
			if(!step(mecha, direction)||mecha.check_for_support())
				src.stop()
		else
			src.stop()
		return

/datum/global_iterator/mecha_internal_damage // processing internal damage

	process(var/obj/mecha/mecha)
		if(!mecha.hasInternalDamage())
			return stop()
		if(mecha.hasInternalDamage(MECHA_INT_FIRE))
			if(!mecha.hasInternalDamage(MECHA_INT_TEMP_CONTROL) && prob(5))
				mecha.clearInternalDamage(MECHA_INT_FIRE)
			if(mecha.internal_tank)
				if(mecha.internal_tank.return_pressure()>mecha.internal_tank.maximum_pressure && !(mecha.hasInternalDamage(MECHA_INT_TANK_BREACH)))
					mecha.setInternalDamage(MECHA_INT_TANK_BREACH)
				var/datum/gas_mixture/int_tank_air = mecha.internal_tank.return_air()
				if(int_tank_air && int_tank_air.volume>0) //heat the air_contents
					int_tank_air.temperature = min(6000+T0C, int_tank_air.temperature+rand(10,15))
			if(mecha.cabin_air && mecha.cabin_air.volume>0)
				mecha.cabin_air.temperature = min(6000+T0C, mecha.cabin_air.temperature+rand(10,15))
				if(mecha.cabin_air.temperature>mecha.max_temperature/2)
					mecha.take_damage(4/round(mecha.max_temperature/mecha.cabin_air.temperature,0.1),"fire")
		if(mecha.hasInternalDamage(MECHA_INT_TEMP_CONTROL)) //stop the mecha_preserve_temp loop datum
			mecha.pr_int_temp_processor.stop()
		if(mecha.hasInternalDamage(MECHA_INT_TANK_BREACH)) //remove some air from internal tank
			if(mecha.internal_tank)
				var/datum/gas_mixture/int_tank_air = mecha.internal_tank.return_air()
				var/datum/gas_mixture/leaked_gas = int_tank_air.remove_ratio(0.10)
				if(mecha.loc && hascall(mecha.loc,"assume_air"))
					mecha.loc.assume_air(leaked_gas)
				else
					qdel(leaked_gas)
		if(mecha.hasInternalDamage(MECHA_INT_SHORT_CIRCUIT))
			if(mecha.get_charge())
				mecha.spark_system.start()
				mecha.cell.charge -= min(20,mecha.cell.charge)
				mecha.cell.maxcharge -= min(20,mecha.cell.maxcharge)
		return


/////////////

//debug
/*
/obj/mecha/verb/test_int_damage()
	set name = "Test internal damage"
	set category = "Exosuit Interface"
	set src in view(0)
	if(!occupant) return
	if(usr!=occupant)
		return
	var/output = {
		"<html><body>
			<h3>Set:</h3>
			<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_FIRE]'>MECHA_INT_FIRE</a><br />
			<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_TEMP_CONTROL]'>MECHA_INT_TEMP_CONTROL</a><br />
			<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_SHORT_CIRCUIT]'>MECHA_INT_SHORT_CIRCUIT</a><br />
			<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_TANK_BREACH]'>MECHA_INT_TANK_BREACH</a><br />
			<a href='?src=\ref[src];debug=1;set_i_dam=[MECHA_INT_CONTROL_LOST]'>MECHA_INT_CONTROL_LOST</a><br />
			<hr/>
			<h3>Clear:</h3>
			<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_FIRE]'>MECHA_INT_FIRE</a><br />
			<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_TEMP_CONTROL]'>MECHA_INT_TEMP_CONTROL</a><br />
			<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_SHORT_CIRCUIT]'>MECHA_INT_SHORT_CIRCUIT</a><br />
			<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_TANK_BREACH]'>MECHA_INT_TANK_BREACH</a><br />
			<a href='?src=\ref[src];debug=1;clear_i_dam=[MECHA_INT_CONTROL_LOST]'>MECHA_INT_CONTROL_LOST</a><br />
		</body></html>
	"}

	occupant << browse(output, "window=ex_debug")
	//src.health = initial(src.health)/2.2
	//src.check_for_internal_damage(list(MECHA_INT_FIRE,MECHA_INT_TEMP_CONTROL,MECHA_INT_TANK_BREACH,MECHA_INT_CONTROL_LOST))
	return
*/

/obj/mecha_cabin
	name = "Operator"
	var/mob/living/carbon/occupant = null
	var/pass_move = 0
	var/obj/mecha/chasis = null

/obj/mecha_cabin/pilot
	name = "Pilot"

/obj/mecha_cabin/New(var/atom/new_loc)
	..()
	if(istype(new_loc, /obj/mecha))
		chasis = new_loc

/obj/mecha_cabin/proc/click_action(var/atom/A, var/mob/living/user)
	(src.occupant != user || user.stat) return
	if(target == chasis) return
	if(state)
		occupant_message("<font color='red'>Maintenance protocols in effect</font>")
		return

	if(!chasis.get_charge()) return
	var/dir_to_target = get_dir(src,target)
	if(dir_to_target && !(dir_to_target & src.dir))//wrong direction
		return

	if(hasInternalDamage(MECHA_INT_CONTROL_LOST))
		target = safepick(view(3,target))
		if(!target)
			return

	if(pass_move && istype(target, /obj/machinery))
		if (chasis.interface_action(target))
			return

	if(!target.Adjacent(chasis))
		if(selected && selected.is_ranged())
			selected.action(target)
	else if(selected && selected.is_melee())
		selected.action(target)
	else if(pass_move)
		chasis.melee_action(target)

	return

/obj/mecha_cabin/proc/interface_action(obj/machinery/target)
	if(istype(target, /obj/machinery/access_button))
		occupant << "<span class='notice'>Interfacing with [target].</span>"
		chasis.log_message("Interfaced with [target].")
		target.attack_hand(src.occupant)
		return 1
	if(istype(target, /obj/machinery/embedded_controller))
		target.ui_interact(src.occupant)
		return 1
	return 0

/obj/mecha_cabin/contents_nano_distance(var/src_object, var/mob/living/user)
	//allow them to interact with anything they can interact with normally.
	. = user.shared_living_nano_distance(chasis)
	if(. != STATUS_INTERACTIVE)
		//Allow interaction with the mecha or anything that is part of the mecha
		if(src_object == chasis || (src_object in chasis))
			return STATUS_INTERACTIVE
		if(chasis.Adjacent(src_object))
			chasis.occupant_message("<span class='notice'>Interfacing with [src_object]...</span>")
			chasis.log_message("Interfaced with [src_object].")
			return STATUS_INTERACTIVE
		if(src_object in view(2, chasis))
			//if they're close enough, allow the occupant to see the screen through the viewport or whatever.
			return STATUS_UPDATE

// Helper stuff

/obj/mecha_cabin/relaymove(mob/user,direction)
	if(pass_move && chasis)
		chasis.relaymove(user, direction)
	return 0

/obj/mecha_cabin/see_emote(mob/living/M, text)
	if(occupant && occupant.client)
		occupant.show_message("<span class='message'>[text]</span>", 2)

// Verbs

/obj/mecha_cabin/proc/connect_to_port()
	set name = "Connect to port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	chasis.try_connect()

/obj/mecha_cabin/proc/disconnect_from_port()
	set name = "Disconnect from port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	chasis.disconnect()

/obj/mecha_cabin/verb/toggle_lights()
	set name = "Toggle Lights"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	chasis.toggle_lights()


// Enter/Exit

/obj/mecha_cabin/proc/moved_inside(var/mob/living/carbon/human/H as mob)

	if(H && H.client && H in range(1, chasis))
		if (C.occupant)
			H << "\blue <B>The [src.name]'s [C.name] is already occupied!</B>"
			chasis.log_append_to_last("Permission denied.")
			return 0
		if((dna && H.dna.unique_enzymes!=dna) && !allowed(H))
			H << "\red Access denied"
			chasis.log_append_to_last("Permission denied.")
			return 0

		if(!do_after(H, 40, needhand = 0))
			H << "You stop entering the exosuit."
			return 0
		if(occupant && occupant!=H)
			H << "[occupant] was faster. Try better next time, loser."
			chasis.log_append_to_last("Permission denied.")
			return 0
		H.reset_view(src)
		H.stop_pulling()
		H.forceMove(src)
		src.occupant = H
		if(!hasInternalDamage())
			src.occupant << sound('sound/mecha/nominal.ogg',volume=50)
		return 1
	else
		return 0

/obj/mecha_cabin/verb/eject()
	set name = "Eject"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	src.go_out()
	chasis.add_fingerprint(usr)
	return


/obj/mecha_cabin/proc/go_out()
	if(!src.occupant) return
	var/atom/movable/mob_container
	if(ishuman(occupant))
		mob_container = src.occupant
	else if(istype(occupant, /mob/living/carbon/brain))
		var/mob/living/carbon/brain/brain = occupant
		mob_container = brain.container
	else
		return
	if(mob_container.forceMove(chasis.loc))
		src.log_message("[mob_container] moved out.")
		occupant.reset_view()
		src.occupant << browse(null, "window=exosuit")
		if(istype(mob_container, /obj/item/device/mmi))
			var/obj/item/device/mmi/mmi = mob_container
			if(mmi.brainmob)
				occupant.loc = mmi
			mmi.mecha = null
			src.occupant.canmove = 0
		src.occupant = null
		mob_container.set_dir(chasis.dir)
	return

// Verbs

/obj/mecha_cabin/verb/view_stats()
	set name = "View Stats"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	//pr_update_stats.start()
	src.occupant << browse(chasis.get_stats_html(), "window=exosuit")
	return

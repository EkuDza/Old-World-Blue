/obj/cabin
	name = "Operator"
	anchored = 1 //no pulling around.
	var/mob/living/carbon/occupant = null
	var/dna	//dna-locking the mech

	var/obj/mecha/chasis = null

	//inner atmos
	var/use_internal_tank = 0

	var/obj/item/device/radio/radio = null

	var/list/equipment = new
	var/obj/item/mecha_parts/mecha_equipment/selected
	var/max_equip = 3
	var/mouse_pointer_icon

/obj/cabin/pilot
	name = "Pilot"

/obj/cabin/pilot/gunner
	mouse_pointer_icon = 'icons/mecha/mecha_mouse.dmi'

/obj/cabin/New(var/atom/new_loc, var/override_max_equip)
	..()
	chasis = new_loc
	if(!istype(chasis))
		qdel(src)
		return null

	add_radio()

	if(override_max_equip)
		max_equip = override_max_equip

/obj/cabin/Destroy()
	go_out()
	..()

/obj/cabin/proc/Death(var/obj/effect/decal/mecha_wreckage/WR = null)
	if(WR)
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			if(E.salvageable && prob(30))
				WR.crowbar_salvage += E
				E.forceMove(WR)
				E.equip_ready = 1
				E.reliability = round(rand(E.reliability/3,E.reliability))
			else
				E.forceMove(loc)
				E.destroy()
	else
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			detach(E, loc)
			E.destroy()
	qdel(src)

/obj/cabin/proc/add_radio()
	radio = new(src)
	radio.name = "[chasis] radio"
	radio.icon = chasis.icon
	radio.icon_state = chasis.icon_state
	radio.subspace_transmission = 1

/obj/cabin/examine(user)
	if(equipment && equipment.len)
	user << "It's [name] cabin equipped with:"
	for(var/obj/item/mecha_parts/mecha_equipment/ME in equipment)
		user << "\icon[ME] [ME]"

//Derpfix, but may be useful in future for engineering exosuits.
/obj/cabin/proc/drop_item()
	return

/obj/cabin/hear_talk(mob/M as mob, text)
	if(M==occupant && radio.broadcasting)
		radio.talk_into(M, text)
	return

/obj/cabin/see_emote(mob/living/M, text)
	if(occupant && occupant.client)
		var/rendered = "<span class='message'>[text]</span>"
		occupant.show_message(rendered, 2)
	..()

/obj/cabin/proc/click_action(atom/target,mob/user)
	if(src.occupant != user ) return
	if(user.stat) return
	if(target == chasis) return 0
	if(!chasis.can_operate()) return

/*
	if(chasis.hasInternalDamage(MECHA_INT_CONTROL_LOST))
		target = safepick(view(3,target))
		if(!target)
			return
*/

	if(istype(target, /obj/machinery))
		if (src.interface_action(target))
			return

	if(!target.Adjacent(src))
		if(selected && selected.is_ranged())
			selected.action(target)
		else
			chasis.range_action()
	else
		if(selected && selected.is_melee())
			selected.action(target)
		else
			chasis.melee_action()


/obj/cabin/proc/interface_action(obj/machinery/target)
	if(istype(target, /obj/machinery/access_button))
		occupant_message("<span class='notice'>Interfacing with [target].</span>")
		chasis.log_message("Interfaced with [target].")
		target.attack_hand(src.occupant)
		return 1
	if(istype(target, /obj/machinery/embedded_controller))
		target.ui_interact(src.occupant)
		return 1
	return 0

/obj/cabin/contents_nano_distance(var/src_object, var/mob/living/user)
	. = user.shared_living_nano_distance(src_object) //allow them to interact with anything they can interact with normally.
	if(. != STATUS_INTERACTIVE)
		//Allow interaction with the mecha or anything that is part of the mecha
		if(src_object == chasis || (src_object in chasis))
			return STATUS_INTERACTIVE
		if(chasis.Adjacent(src_object))
			occupant_message("<span class='notice'>Interfacing with [src_object]...</span>")
			chasis.log_message("Interfaced with [src_object].")
			return STATUS_INTERACTIVE
		if(src_object in view(2, chasis))
			return STATUS_UPDATE //if they're close enough, allow the occupant to see the screen through the viewport or whatever.

/obj/cabin/pilot/relaymove(mob/user,direction)
	chasis.relaymove(user, direction)

///////////////////////
////// Equipment //////
///////////////////////
/obj/cabin/proc/can_attach(var/obj/item/mecha_parts/mecha_equipment/E)
	if(!istype(E) || (equipment.len >= max_equip))
		return 0

/obj/cabin/proc/attach(var/obj/item/mecha_parts/mecha_equipment/E, mob/living/user)
	if(user)
		user.drop_from_inventory(E, src)
		user.visible_message("[user] attaches [E] to [src]", "You attach [E] to [src]")
	E.forceMove(src)
	equipment += E
	chasis.log_message("[E] initialized ([src]).")
	if(!selected)
		selected = E
	E.attached(chasis)

/obj/cabin/proc/detach(var/obj/item/mecha_parts/mecha_equipment/E, atom/moveto=null)
	if(!E || !E in equipment)
		return
	moveto = moveto || get_turf(src)
	if(E.detached())
		E.Move(moveto)
		equipment -= E
		if(selected == E)
			selected = null
		chasis.log_message("[E] removed from [src] equipment.")
	return

/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/cabin/proc/get_turf_air()
	return chasis.get_turf_air()

/obj/cabin/remove_air(amount)
	if(use_internal_tank)
		return chasis.cabin_air.remove(amount)
	else
		var/turf/T = get_turf(src)
		if(T)
			return T.remove_air(amount)
	return

/obj/cabin/return_air()
	if(use_internal_tank)
		return chasis.cabin_air
	return ..()

/obj/cabin/proc/return_pressure()
	. = 0
	if(use_internal_tank)
		. =  chasis.cabin_air.return_pressure()
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.return_pressure()
	return

/obj/cabin/proc/return_temperature()
	. = 0
	if(use_internal_tank)
		. = chasis.cabin_air.temperature
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.temperature
	return

/////////////////////////
////////  Verbs  ////////
/////////////////////////


/obj/cabin/proc/connect_to_port()
	set name = "Connect to port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	var/obj/machinery/atmospherics/portables_connector/possible_port = locate() in chasis.loc
	if(possible_port)
		if(chasis.connect(possible_port))
			occupant_message("\blue [name] connects to the port.")
			return 1
		else
			occupant_message("\red [name] failed to connect to the port.")
			return
	else
		occupant_message("Nothing happens")
	return 0

/obj/cabin/proc/disconnect_from_port()
	set name = "Disconnect from port"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	chasis.disconnect(src)

/obj/cabin/verb/toggle_lights()
	set name = "Toggle Lights"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=occupant)	return
	chasis.toggle_lights()

/obj/cabin/verb/toggle_internal_tank()
	set name = "Toggle internal airtank usage."
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	use_internal_tank = !use_internal_tank
	occupant_message("Now taking air from [use_internal_tank?"internal airtank":"environment"].")
	chasis.log_message("[src] now taking air from [use_internal_tank?"internal airtank":"environment"].")
	return

/obj/cabin/proc/move_inside(var/mob/living/carbon/human/H)
	if (src.occupant)
		H << "\blue <B>The [src.name] is already occupied!</B>"
		chasis.log_append_to_last("Permission denied.")
		return

	var/passed
	if(src.dna)
		if(H.dna.unique_enzymes==src.dna)
			passed = 1
	else if(chasis.allow(H))
		passed = 1
	if(!passed)
		H << "\red Access denied"
		chasis.log_append_to_last("Permission denied.")
		return

	visible_message("\blue [usr] starts to climb into [src.name]")

	if(do_after(usr, 40, chasis))
		if(!src.occupant)
			moved_inside(usr)
		else if(src.occupant!=usr)
			usr << "[src.occupant] was faster. Try better next time, loser."
	else
		usr << "You stop entering the exosuit."
	return

/obj/cabin/proc/moved_inside(var/mob/living/carbon/human/H as mob)
	if(H && H.client && H in range(1))
		if(mouse_pointer_icon && H.client)
			H.client.mouse_pointer_icon = mouse_pointer_icon
		H.reset_view(src)
		H.stop_pulling()
		H.forceMove(src)
		src.occupant = H
		src.add_fingerprint(H)
		chasis.log_append_to_last("[H] moved in as [src].")
		playsound(src, 'sound/machines/windowdoor.ogg', 50, 1)
		if(!chasis.hasInternalDamage())
			src.occupant << sound('sound/mecha/nominal.ogg',volume=50)
		return 1
	else
		return 0

/obj/cabin/verb/view_stats()
	set name = "View Stats"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	//pr_update_stats.start()
	src.occupant << browse(src.get_stats_html(), "window=exosuit")
	return

/obj/cabin/verb/eject()
	set name = "Eject"
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	src.go_out()
	add_fingerprint(usr)
	return

/obj/cabin/proc/go_out()
	if(!src.occupant) return
	var/atom/movable/mob_container
	if(ishuman(occupant))
		mob_container = src.occupant
	else if(istype(occupant, /mob/living/carbon/brain))
		var/mob/living/carbon/brain/brain = occupant
		mob_container = brain.container
	else
		return
	if(mob_container.forceMove(chasis.loc))//ejecting mob container
		if(src.occupant.client)
			src.occupant.client.mouse_pointer_icon = initial(src.occupant.client.mouse_pointer_icon)
		chais.log_message("[mob_container] moved out.")
		occupant.reset_view()
		src.occupant << browse(null, "window=exosuit")
		if(istype(mob_container, /obj/item/device/mmi))
			var/obj/item/device/mmi/mmi = mob_container
			if(mmi.brainmob)
				occupant.loc = mmi
			mmi.mecha = null
			src.occupant.canmove = 0
		src.occupant = null
		src.set_dir(chasis.dir)
	return


////////////////////////////////////
///// Rendering stats window ///////
////////////////////////////////////

/obj/cabin/proc/get_stats_html()
	var/output = {"
		<html>
			<head><title>[src.name] data</title>
			<style>
			body {color: #00ff00; background: #000000; font-family:"Lucida Console",monospace; font-size: 12px;}
			hr {border: 1px solid #0f0; color: #0f0; background-color: #0f0;}
			a {padding:2px 5px;;color:#0f0;}
			.wr {margin-bottom: 5px;}
			.header {cursor:pointer;}
			.open, .closed {background: #32CD32; color:#000; padding:1px 2px;}
			.links a {margin-bottom: 2px;padding-top:3px;}
			.visible {display: block;}
			.hidden {display: none;}
			</style>
			<script language='javascript' type='text/javascript'>
			[js_byjax]
			[js_dropdowns]
			function ticker() {
				setInterval(function(){
					window.location='byond://?src=\ref[src]&update_content=1';
				}, 1000);
			}
			window.onload = function() {
				dropdowns();
				ticker();
			}
			</script>
		</head>
		<body>
			<div id='content'>
				[src.get_stats_part()]
			</div>
			<div id='eq_list'>
				[src.get_equipment_list()]
			</div>
			<hr>
			<div id='commands'>
				[src.get_commands()]
			</div>
		</body>
		</html>
	"}
	return output

/obj/cabin/proc/get_stats_part()
	var/output = chasis.get_stats_part()
	if(return_pressure() > WARNING_HIGH_PRESSURE)
		output += "<font color='red'><b>DANGEROUSLY HIGH CABIN PRESSURE</b></font><br />"

	var/tank_pressure = chasis.internal_tank ? round(chasis.internal_tank.return_pressure(),0.01) : "None"
	var/tank_temperature = chasis.internal_tank ? chasis.internal_tank.return_temperature() : "Unknown"
	var/cabin_pressure = round(return_pressure(),0.01)
	output += {"
		<b>Air source: </b>[use_internal_tank?"Internal Airtank":"Environment"]<br>
		<b>Airtank pressure: </b>[chasis.tank_pressure]kPa<br>
		<b>Airtank temperature: </b>[chasis.tank_temperature]K|[chasis.tank_temperature - T0C]&deg;C<br>
		<b>Cabin pressure: </b>[chasis.cabin_pressure>WARNING_HIGH_PRESSURE ? "<font color='red'>[chasis.cabin_pressure]</font>": chasis.cabin_pressure]kPa<br>
		<b>Cabin temperature: </b> [chasis.return_temperature()]K|[chasis.return_temperature() - T0C]&deg;C<br>
		[src.dna?"<b>DNA-locked:</b><br> <span style='font-size:10px;letter-spacing:-1px;'>[src.dna]</span> \[<a href='?src=\ref[src];reset_dna=1'>Reset</a>\]<br>":null]
	"}
	return output

/obj/cabin/proc/get_commands()
	var/output = {"
		<div class='wr'>
			<div class='header'>Electronics</div>
			<div class='links'>
				<a href='?src=\ref[src];toggle_lights=1'>Toggle Lights</a><br>
				<b>Radio settings:</b><br>
				Microphone: <a href='?src=\ref[src];rmictoggle=1'><span id="rmicstate">[radio.broadcasting?"Engaged":"Disengaged"]</span></a><br>
				Speaker: <a href='?src=\ref[src];rspktoggle=1'><span id="rspkstate">[radio.listening?"Engaged":"Disengaged"]</span></a><br>
				Frequency:
				<a href='?src=\ref[src];rfreq=-10'>-</a>
				<a href='?src=\ref[src];rfreq=-2'>-</a>
				<span id="rfreq">[format_frequency(radio.frequency)]</span>
				<a href='?src=\ref[src];rfreq=2'>+</a>
				<a href='?src=\ref[src];rfreq=10'>+</a><br>
			</div>
		</div>
		<div class='wr'>
			<div class='header'>Airtank</div>
			<div class='links'>
				<a href='?src=\ref[src];toggle_airtank=1'>Toggle Internal Airtank Usage</a><br>
				if(/obj/cabin/verb/disconnect_from_port in src.verbs)
					"<a href='?src=\ref[src];port_disconnect=1'>Disconnect from port</a><br>"
				else
					"<a href='?src=\ref[src];port_connect=1'>Connect to port</a><br>"
			</div>
		</div>
		<div class='wr'>
			<div class='header'>Permissions & Logging</div>
			<div class='links'>
				<a href='?src=\ref[src];toggle_id_upload=1'><span id='t_id_upload'>[chasis.add_req_access?"L":"Unl"]ock ID upload panel</span></a><br>
				<a href='?src=\ref[src];toggle_maint_access=1'><span id='t_maint_access'>[chasis.maint_access?"Forbid":"Permit"] maintenance protocols</span></a><br>
				<a href='?src=\ref[src];dna_lock=1'>DNA-lock</a><br>
				<a href='?src=\ref[src];view_log=1'>View internal log</a><br>
				<a href='?src=\ref[src];change_name=1'>Change exosuit name</a><br>
			</div>
		</div>
		<div id='equipment_menu'>[get_equipment_menu()]</div>
		<hr>
		[(/obj/cabin/verb/eject in src.verbs)?"<a href='?src=\ref[src];eject=1'>Eject</a><br>":null]
	"}
	return output


//outputs mecha html equipment menu
/obj/cabin/proc/get_equipment_menu()
	var/output
	if(equipment.len)
		output += {"
			<div class='wr'>
			<div class='header'>Equipment</div>
			<div class='links'>
		"}
		for(var/obj/item/mecha_parts/mecha_equipment/W in equipment)
			output += "[W.name] <a href='?src=\ref[W];detach=1'>Detach</a><br>"
		output += "<b>Available equipment slots:</b> [max_equip-equipment.len]"
		output += "</div></div>"
	return output


//outputs mecha equipment list in html
/obj/cabin/proc/get_equipment_list()
	if(!equipment.len)
		return
	var/output = "<b>Equipment:</b><div style=\"margin-left: 15px;\">"
	for(var/obj/item/mecha_parts/mecha_equipment/MT in equipment)
		output += "<div id='\ref[MT]'>[MT.get_equip_info()]</div>"
	output += "</div>"
	return output

/obj/cabin/proc/occupant_message(message as text)
	if(message)
		if(src.occupant && src.occupant.client)
			src.occupant << message
	return

/obj/cabin/Topic(href, href_list)
	..()
	if(usr != src.occupant) return
	if(href_list["update_content"])
		send_byjax(src.occupant,"exosuit.browser","content",src.get_stats_part())
		return
	if(href_list["close"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		return
	var/datum/topic_input/filter = new (href,href_list)
	if(href_list["select_equip"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		var/obj/item/mecha_parts/mecha_equipment/equip = filter.getObj("select_equip")
		if(equip)
			src.selected = equip
			src.occupant_message("You switch to [equip]")
			src.visible_message("[src] raises [equip]")
			send_byjax(src.occupant,"exosuit.browser","eq_list",src.get_equipment_list())
		return
	if(href_list["detach"])
		detach(filter.getObj("detach"))
	if(href_list["eject"])
		playsound(src,'sound/mecha/ROBOTIC_Servo_Large_Dual_Servos_Open_mono.wav',100,1)
		src.eject()
		return
	if(href_list["toggle_lights"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		src.toggle_lights()
		return
	if(href_list["toggle_airtank"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		src.toggle_internal_tank()
		return
	if(href_list["rmictoggle"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		radio.broadcasting = !radio.broadcasting
		send_byjax(src.occupant,"exosuit.browser","rmicstate",(radio.broadcasting?"Engaged":"Disengaged"))
		return
	if(href_list["rspktoggle"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		radio.listening = !radio.listening
		send_byjax(src.occupant,"exosuit.browser","rspkstate",(radio.listening?"Engaged":"Disengaged"))
		return
	if(href_list["rfreq"])
		var/new_frequency = (radio.frequency + filter.getNum("rfreq"))
		if (!radio.freerange || (radio.frequency < 1200 || radio.frequency > 1600))
			new_frequency = sanitize_frequency(new_frequency)
		radio.set_frequency(new_frequency)
		send_byjax(src.occupant,"exosuit.browser","rfreq","[format_frequency(radio.frequency)]")
		return
	if(href_list["port_disconnect"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		src.disconnect_from_port()
		return
	if (href_list["port_connect"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		src.connect_to_port()
		return
	if (href_list["view_log"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		src.occupant << browse(chasis.get_log_html(), "window=exosuit_log")
		onclose(occupant, "exosuit_log")
		return
	if (href_list["change_name"])
		var/newname = sanitizeSafe(input(occupant,"Choose new exosuit name","Rename exosuit",initial(chasis.name)) as text, MAX_NAME_LEN)
		if(newname)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.wav',channel=4, volume=100);
			chasis.name = newname
		else
			alert(occupant, "nope.avi")
		return
	if (href_list["toggle_id_upload"])
		chasis.add_req_access = !chasis.add_req_access
		send_byjax(src.occupant,"exosuit.browser","t_id_upload","[chasis.add_req_access?"L":"Unl"]ock ID upload panel")
		return
	if(href_list["toggle_maint_access"])
		if(usr != src.occupant)	return
		if(state)
			occupant_message("<font color='red'>Maintenance protocols in effect</font>")
			return
		chasis.maint_access = !chasis.maint_access
		send_byjax(src.occupant,"exosuit.browser","t_maint_access","[chasis.maint_access?"Forbid":"Permit"] maintenance protocols")
		return
	if(href_list["dna_lock"])
		if(istype(occupant, /mob/living/carbon/brain))
			occupant_message("You are a brain. No.")
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.wav',channel=4, volume=100);
			return
		if(src.occupant)
			src.dna = src.occupant.dna.unique_enzymes
			src.occupant_message("You feel a prick as the needle takes your DNA sample.")
			usr << sound('sound/mecha/UI_SCI-FI_Compute_01_Wet_stereo.wav',channel=4, volume=100);
		return
	if(href_list["reset_dna"])
		src.dna = null
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
	if(href_list["repair_int_control_lost"])
		chasis.occupant_message("Recalibrating coordination system.")
		src.log_message("Recalibration of coordination system started.")
		chasis.try_fix_control()
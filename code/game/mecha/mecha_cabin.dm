/obj/mecha_cabin
	name = "Operator"
	var/mob/living/carbon/occupant = null
	var/pass_move = 0
	var/obj/mecha/chasis = null
	var/use_internal_tank = 0
	var/dna	//dna-locking cabin
	var/obj/item/device/radio/radio = null

	var/list/equipment = new
	var/obj/item/mecha_parts/mecha_equipment/selected

/obj/mecha_cabin/pilot
	name = "Pilot"

/obj/mecha_cabin/New(var/atom/new_loc)
	..()
	if(istype(new_loc, /obj/mecha))
		chasis = new_loc
		radio = new(src)
		radio.name = "[chasis] radio"
		radio.icon = chasis.icon
		radio.icon_state = chasis.icon_state
		radio.subspace_transmission = 1

/obj/mecha_cabin/proc/destroy(var/obj/effect/decal/mecha_wreckage/WR)
	go_out()

	for(var/mob/M in src) //Let's just be ultra sure
		M.Move(chasis.loc)

	if(WR)
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			if(E.salvageable && prob(30))
				WR.crowbar_salvage += E
				E.forceMove(WR)
				E.detached()
			else
				E.forceMove(loc)
				E.destroy()
		for(var/obj/item/mecha_parts/mecha_equipment/E in equipment)
			detach(E, loc)
			E.destroy()


	chassis.occupant_message("<font color='red'>The [src] is destroyed!</font>")
	chassis.log_append_to_last("[src] is destroyed.",1)


/obj/mecha_cabin/proc/click_action(var/atom/A, var/mob/living/user)
	if(src.occupant != user || user.stat) return
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

/////////////////////////////////////
////////  Atmospheric stuff  ////////
/////////////////////////////////////

/obj/mecha_cabin/proc/get_turf_air()
	var/turf/T = get_turf(src)
	if(T)
		. = T.return_air()
	return

/obj/mecha_cabin/remove_air(amount)
	if(use_internal_tank)
		return cabin_air.remove(amount)
	else
		var/turf/T = get_turf(src)
		if(T)
			return T.remove_air(amount)
	return

/obj/mecha_cabin/return_air()
	if(use_internal_tank)
		return cabin_air
	return get_turf_air()

/obj/mecha_cabin/proc/return_pressure()
	. = 0
	if(use_internal_tank)
		. =  cabin_air.return_pressure()
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.return_pressure()
	return

/obj/mecha_cabin/proc/return_temperature()
	. = 0
	if(use_internal_tank)
		. = cabin_air.temperature
	else
		var/datum/gas_mixture/t_air = get_turf_air()
		if(t_air)
			. = t_air.temperature
	return


///////////////////////////////
////////  Interaction  ////////
///////////////////////////////

/obj/mecha_cabin/relaymove(mob/user,direction)
	if(pass_move && chasis)
		chasis.relaymove(user, direction)
	return 0

/obj/mecha_cabin/see_emote(mob/living/M, text)
	if(occupant && occupant.client)
		occupant.show_message("<span class='message'>[text]</span>", 2)


//////////////////////////////
////////  Enter/Exit  ////////
//////////////////////////////

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

/obj/mecha_cabin/verb/toggle_internal_tank()
	set name = "Toggle internal airtank usage."
	set category = "Exosuit Interface"
	set src = usr.loc
	set popup_menu = 0
	if(usr!=src.occupant)
		return
	use_internal_tank = !use_internal_tank
	chsis.occupant_message("[src] taking air from [use_internal_tank?"internal airtank":"environment"].")
	chasis.log_message("[src] now taking air from [use_internal_tank?"internal airtank":"environment"].")
	return



////////////////////////////////////
///// Rendering stats window ///////
////////////////////////////////////

/obj/mecha/proc/get_stats_html()
	var/output = {"
		<html>
		<head><title>[chasis.name] data</title>
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
			<div id='content'>[src.get_stats_part()]</div>
			<div id='eq_list'>[src.get_equipment_list()]</div>
			<hr>
			<div id='commands'>[src.get_commands()]</div>
		</body>
		</html>
	 "}
	return output


/obj/mecha_cabin/proc/report_internal_damage()
	. = chasis.report_internal_damage()
	if(return_pressure() > WARNING_HIGH_PRESSURE)
		. += "<font color='red'><b>DANGEROUSLY HIGH CABIN PRESSURE</b></font><br />"
	return

/obj/mecha_cabin/proc/get_stats_part()
	var/output = ..()
	var/cabin_pressure = round(return_pressure(),0.01)
	output = {"
		[report_internal_damage()]
		[output]
		<b>Cabin pressure: </b>[cabin_pressure>WARNING_HIGH_PRESSURE ? "<font color='red'>[cabin_pressure]</font>": cabin_pressure]kPa<br>
		<b>Cabin temperature: </b> [return_temperature()]K|[return_temperature() - T0C]&deg;C<br>
		<b>Lights: </b>[lights?"on":"off"]<br>
		[src.dna?"<b>DNA-locked:</b><br> \
		<span style='font-size:10px;letter-spacing:-1px;'>[src.dna]</span> \[<a href='?src=\ref[src];reset_dna=1'>Reset</a>\]<br>":null]
	"}
	return output

/obj/mecha_cabin/proc/get_commands()
	var/output = {"
		<div class='wr'>
			<div class='header'>Electronics</div>
			<div class='links'>
				<a href='?src=\ref[src];toggle_lights=1'>Toggle Lights</a><br>
				<b>Radio settings:</b><br>
				Microphone: <a href='?src=\ref[src];rmictoggle=1'>
					<span id="rmicstate">[radio.broadcasting?"Engaged":"Disengaged"]</span></a><br>
				Speaker: <a href='?src=\ref[src];rspktoggle=1'>
					<span id="rspkstate">[radio.listening?"Engaged":"Disengaged"]</span></a><br>
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
				[chasis.connected_port\
					? "<a href='?src=\ref[src];port_disconnect=1'>Disconnect from port</a><br>"\
					: "<a href='?src=\ref[src];port_connect=1'>Connect to port</a><br>"]
			</div>
		</div>
		<div class='wr'>
			<div class='header'>Permissions & Logging</div>
			<div class='links'>
				<a href='?src=\ref[src];toggle_id_upload=1'>
					<span id='t_id_upload'>[add_req_access?"L":"Unl"]ock ID upload panel</span></a><br>
				<a href='?src=\ref[src];toggle_maint_access=1'>
					<span id='t_maint_access'>[maint_access?"Forbid":"Permit"] maintenance protocols</span></a><br>
				<a href='?src=\ref[src];dna_lock=1'>DNA-lock</a><br>
				<a href='?src=\ref[src];view_log=1'>View internal log</a><br>
				<a href='?src=\ref[src];change_name=1'>Change exosuit name</a><br>
			</div>
		</div>
		<div id='equipment_menu'>[get_equipment_menu()]</div>
		<hr>
		<a href='?src=\ref[src];eject=1'>Eject</a><br>
	"}
	return output

/obj/mecha_cabin/proc/get_equipment_menu() //outputs mecha html equipment menu
	var/output
	if(equipment.len)
		output += {"
			<div class='wr'>
			<div class='header'>Equipment</div>
			<div class='links'>
		"}
		for(var/obj/item/mecha_parts/mecha_equipment/W in equipment)
			output += "[W.name] <a href='?src=\ref[src];detach=\ref[W]'>Detach</a><br>"
		output += "<b>Available equipment slots:</b> [max_equip-equipment.len]"
		output += "</div></div>"
	return output

/obj/mecha_cabin/proc/get_equipment_list() //outputs mecha equipment list in html
	if(!equipment.len)
		return
	var/output = "<b>Equipment:</b><div style=\"margin-left: 15px;\">"
	for(var/obj/item/mecha_parts/mecha_equipment/MT in equipment)
		output += "<div id='\ref[MT]'>[MT.get_equip_info()]</div>"
	output += "</div>"
	return output


/////////////////
///// Topic /////
/////////////////

/obj/mecha_cabin/Topic(href, href_list)
	..()
	if(usr != src.occupant)	return
	if(href_list["update_content"])
		send_byjax(src.occupant,"exosuit.browser","content",src.get_stats_part())
		return
	if(href_list["close"])
		usr << sound('sound/mecha/UI_SCI-FI_Tone_10_stereo.wav',channel=4, volume=100);
		return
	if(usr.stat > 0)
		return
	var/datum/topic_input/filter = new /datum/topic_input(href,href_list)
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
		var/obj/item/mecha_parts/mecha_equipment/E = locate(href_list["detach"])
		detach(E)
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
		var/newname = sanitizeSafe(input(occupant,"Choose new exosuit name","Rename exosuit",initial(name)) as text, MAX_NAME_LEN)
		if(newname)
			usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.wav',channel=4, volume=100);
			chasis.name = newname
		else
			alert(occupant, "nope.avi")
		return
	if (href_list["toggle_id_upload"])
		add_req_access = !add_req_access
		send_byjax(src.occupant,"exosuit.browser","t_id_upload","[add_req_access?"L":"Unl"]ock ID upload panel")
		return
	if(href_list["toggle_maint_access"])
		if(state)
			chasis.occupant_message("<font color='red'>Maintenance protocols in effect</font>")
			return
		maint_access = !maint_access
		send_byjax(src.occupant,"exosuit.browser","t_maint_access","[maint_access?"Forbid":"Permit"] maintenance protocols")
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
		src.occupant_message("Recalibrating coordination system.")
		src.log_message("Recalibration of coordination system started.")
		usr << sound('sound/mecha/UI_SCI-FI_Compute_01_Wet_stereo.wav',channel=4, volume=100);
		var/T = src.loc
		if(do_after(100))
			if(T == src.loc)
				chasis.clearInternalDamage(MECHA_INT_CONTROL_LOST)
				usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_22_stereo_complite.wav',channel=4, volume=100);
				chasis.occupant_message("<font color='blue'>Recalibration successful.</font>")
				chasis.log_message("Recalibration of coordination system finished with 0 errors.")
			else
				usr << sound('sound/mecha/UI_SCI-FI_Tone_Deep_Wet_15_stereo_error.wav',channel=4, volume=100);
				chasis.occupant_message("<font color='red'>Recalibration failed.</font>")
				chasis.log_message("Recalibration of coordination system failed with 1 error.",1)



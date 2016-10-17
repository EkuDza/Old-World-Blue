mob/living/carbon/verb/give()
	set category = "IC"
	set name = "Give"

	if(usr.stat)
		return
	var/obj/item/I = src.get_active_hand()
	if(!I)
		src << "<span class='warning'>You don't have anything in your hands!</span>"
		return

	var/mob/living/carbon/target = input("Give to whom?", "Target") in view(1)-usr
	if(!istype(target) || target.stat || target.lying || target.resting || target.client == null)
		return

	if(!Adjacent(target))
		src << "<span class='warning'>You need to stay in reaching distance while giving an object.</span>"
		if(src in view(target))
			target << "<span class='notice'>[src] tried to give you something.</span>"
		return

	if(alert(target,"[src] wants to give you \a [I]. Will you accept it?",,"Yes","No") == "No")
		target.visible_message("<span class='notice'>\The [src] tried to hand \the [I] to \the [target], \
		but \the [target] didn't want it.</span>")
		return

	if(!I) return

	if(!Adjacent(target))
		src << "<span class='warning'>You need to stay in reaching distance while giving an object.</span>"
		target << "<span class='warning'>\The [src] moved too far away.</span>"
		return

	if(I.loc != src || ! I in list(l_hand, r_hand))
		src << "<span class='warning'>You need to keep the item in your hands.</span>"
		target << "<span class='warning'>\The [src] seems to have given up on passing \the [I] to you.</span>"
		return

	if(target.l_hand && target.r_hand)
		target << "<span class='warning'>Your hands are full.</span>"
		src << "<span class='warning'>Their hands are full.</span>"
		return

	if(src.unEquip(I))
		target.put_in_hands(I) // If this fails it will just end up on the floor, but that's fitting for things like dionaea.
		target.visible_message("<span class='notice'>\The [src] handed \the [I] to \the [target].</span>")

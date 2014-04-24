class PDFTextHighlight extends Annotator.Highlight
  # Is this element a text highlight physical anchor?
  @isInstance: (element) =>
    false

  constructor: (anchor, pageIndex, @normedRange) ->
    super anchor, pageIndex

    @_$textLayer = $(@normedRange.commonAncestor).closest('.text-layer')
    @_$highlightsLayer = @_$textLayer.prev('.highlights-layer')
    @_highlightsCanvas = @_$highlightsLayer.prev('.highlights-canvas').get(0)
    @_$highlightsControl = @_$textLayer.next('.highlights-control')

    @_offset = @_$highlightsLayer.offsetParent().offset()

    @_area = null
    @_box = null
    @_hover = null
    @_$highlight = null

    # We are displaying hovering effect also when mouse is not really over the highlighting, but we
    # have to know if mouse is over the highlight to know if we should remove or not the hovering effect
    # TODO: Rename hovering effect to something else (engaged? active?) and then hovering and other actions should just engage highlight as neccessary
    # TODO: Sync this naming terminology with annotations (there are same states there)
    @_mouseHovering = false

    @_createHighlight()

  _computeArea: (segments) =>
    @_area = 0

    for segment in segments
      @_area += segment.width * segment.height

    return # Don't return the result of the for loop

  _boundingBox: (segments) =>
    @_box = _.clone segments[0]

    for segment in segments[1..]
      if segment.left < @_box.left
        @_box.width += @_box.left - segment.left
        @_box.left = segment.left
      if segment.top < @_box.top
        @_box.height += @_box.top - segment.top
        @_box.top = segment.top
      if segment.left + segment.width > @_box.left + @_box.width
        @_box.width = segment.left + segment.width - @_box.left
      if segment.top + segment.height > @_box.top + @_box.height
        @_box.height = segment.top + segment.height - @_box.top

  _precomputeHover: (segments) =>
    # TODO: Improve polygon drawing, split segment array by chunks

    ## _hover is an array of vertices coordinates
    #@_hover = []
    #@_hover.push([Math.round(segments[0].left), Math.round(segments[0].top + segments[0].height)])
    #@_hover.push([Math.round(segments[0].left), Math.round(segments[0].top)])

    #before 4-9-14
    #merge the row
    l = segments.length
    temp = []
    for segment in segments
      temp.push([_.clone(segment),true])
    i = l-1
    while i>=0
      current = temp[i][0]
      currentleft = current.left
      currentright = current.left+current.width
      currenttop = current.top
      currentbottom = current.top+current.height
      j = i-1
      while j>=0 and temp[i][1]
        compare = temp[j][0]
        compareleft = compare.left
        compareright = compare.left+compare.width
        comparetop = compare.top
        comparebottom = compare.top+compare.height
        if ((currentleft-compareright<=15) and (currentleft-compareright>-1)) or ((compareleft <= currentleft) and (currentleft <=compareright) and (compareright <=currentright)) #need to try some numbers
          if currenttop <= comparetop and comparetop <= currentbottom
            temp[j][0].top = currenttop
            temp[j][0].width = currentright-temp[j][0].left
            if comparebottom <= currentbottom
              temp[j][0].height = currentbottom-temp[j][0].top
            else 
              temp[j][0].height = comparebottom-temp[j][0].top
            temp[i][1] = false
          else if comparetop <= currenttop and currenttop <= comparebottom
            temp[j][0].width = currentright-temp[j][0].left
            if comparebottom <= currentbottom
              temp[j][0].height = currentbottom-temp[j][0].top
            temp[i][1] = false
        j--
      i--
    #finish merging the row
    #define temp2 to be the the merged row of the form (segment,true).
    temp2 = []
    for segment in temp
      temp2.push(segment) if segment[1]

    #4-9-14
    #check if any box is contained in any other box
    i = 0
    while i < temp2.length and temp2[i][1]
      current = temp2[i][0]
      currentleft = current.left
      currentright = current.left+current.width
      currenttop = current.top
      currentbottom = current.top+current.height      
      j = 0
      while j < temp2.length and temp2[i][1] and temp2[j][1]
        if j isnt i
          compare = temp2[j][0]
          compareleft = compare.left
          compareright = compare.left+compare.width
          comparetop = compare.top
          comparebottom = compare.top+compare.height
          if (currentleft+1 >= compareleft) and (currentright<= compareright+1) and (currenttop+1>= comparetop) and (currentbottom <= comparebottom+1)
            temp2[i][1] = false
          if (currentleft <= compareleft+1) and (currentright+1>= compareright) and (currenttop<= comparetop+1) and (currentbottom+1 >= comparebottom)
            temp2[j][1] = false
        j++
      i++

    #4-16-14
    #define temp3 to be the merged row in the form (segment0,segment1,segment2, true, number), number: 1=rectangle, 2=topRow+middle, 3=middle+bottomRow, 4=topRow+middle+bottomRow, 5=topRow+bottomRow, fill three segments from the left to the right, according to the number. e.g., number = 1, then segment0 = segment1 = segment2.
    #merge from the top row to the bottom row, merged row in the top.
    #temp3 = []
    #for segment in temp2
    #  temp3.push([segment[0],segment[0],segment[0],segment[1],1]) if segment[1]
    #l = temp3.length
    #i = 0
    #while i < l and temp3[i][3]
    #  currenttype = temp3[i][4]
    #  j = i+1
    #  while j < l and temp3[j][3]
    #    comparetype = temp3[j][4]
    #    if (currenttype is 1) and (comparetype is 1)
    #      current = temp3[i][0]
    #      currentleft = current.left
    #      currentright = current.left+current.width
    #      currenttop = current.top
    #      currentbottom = current.top+current.height
    #      compare = temp3[j][0]
    #      compareleft = compare.left
    #      compareright = compare.left+compare.width
    #      comparetop = compare.top
    #      comparebottom = compare.top+compare.height
    #      if (comparebottom-currentbottom<5) and (comparebottom - currentbottom > -1) #ready to merge
    #        if (currentleft-compareleft >1) and (currentright-compareright<1) and (currentright-compareright>-1)
    #          temp3[i][1]= temp3[j][0]
    #          temp3[i][4]= 2
    #          temp3[j][3]= false
    #        if (currentleft
    #    j++
    #  i++

    ##4-9-14
    #@_hover = []
    #k = 0
    #while k < temp2.length
    #  @_hover.push(temp2[k][0]) if temp2[k][1]
    #  k++
    
    #4-23-14 merge blocks
    temp2.sort (a,b) ->
      return if (((a[0].left+a[0].width)<=b[0].left) or (((a[0].left+a[0].width)>b[0].left) and (a[0].top<=b[0].top))) then -1 else 1 
    
    #temp3 is going to group neighbour rows together
    temp3 = []
    i = 0
    while i < temp2.length 
      temp3.push([_.clone(temp2[i][0]),i]) #(segment, group number)
      i++
    L = temp3.length
    swap = 1 #count the number of swaps
    while swap > 0
      swap = 0
      j = 0 #run over temp3
      while j < L
        k = j
        while k < L
          current = temp3[j][0]
          currentleft = current.left
          currentright = current.left+current.width
          currenttop = current.top
          currentbottom = current.top+current.height        
          compare = temp3[k][0]
          compareleft = compare.left
          compareright = compare.left+compare.width
          comparetop = compare.top
          comparebottom = compare.top+compare.height
          if (((comparetop-currentbottom <=5) and (comparetop-currentbottom >=-1)) or ((currenttop<=comparetop+2) and (comparetop<=currentbottom+2) and (currentbottom<=comparebottom+2)) or ((currentbottom-comparetop<=5) and (currentbottom-comparetop>=-1)) or ((comparetop<=currenttop+2) and (currenttop<=comparebottom+2) and (comparebottom<=currentbottom+2))) and ((not (currentleft-compareright>15)) and (not (compareleft-currentright>15)) and (temp3[k][1] isnt temp3[j][1])) #conditions for two rows to merge
            t = _.clone(temp3[k][1])
            temp3[k][1] = temp3[j][1]
            m = 0
            while m < L
              temp3[m][1] = temp3[j][1] if (temp3[m][1] is t)
              m++
            swap++
          k++
        j++

    #define temp4 to be grouped rows [[row1,row3,row6],[row2,row4],[row5]]
    temp4 = []
    i = 0
    while i < L #i is group number
      temp5 = []
      j = 0
      while j < L
        if temp3[j][1] is i
          temp5.push(_.clone(temp3[j][0]))
        j++
      temp4.push(_.clone(temp5)) if temp5.length>0
      i++

    #for each group, find the convex hull
    @_hover = []
    L = temp4.length
    i = 0
    while i < L #i is the group number, for each i, generate an element for drawing in hover
      hoverelt = []
      upperleft = []
      upperright = []
      lowerleft = []
      lowerright = []
      l = temp4[i].length
      j = 0
      while j < l #j is the number of element in the group
        upperleft.push([temp4[i][j].left,temp4[i][j].top])
        upperright.push([temp4[i][j].left+temp4[i][j].width,temp4[i][j].top])
        lowerleft.push([temp4[i][j].left,temp4[i][j].top+temp4[i][j].height])
        lowerright.push([temp4[i][j].left+temp4[i][j].width,temp4[i][j].top+temp4[i][j].height])
        j++

      upperright.sort (a,b) ->
        return if (a[1]<b[1] or (a[1] is b[1] and a[0]<b[0])) then -1 else 1
      hoverelt_ur = [] 
      j = 0
      while j < l #compare horizontally
        witness = false #witness is false if j'th elt can fill in
        k = 0
        while k < j and not witness
          witness = true if (upperright[j][0]<= upperright[k][0])
          k++
        k = j+1
        while k < l and not witness
          witness = true if (upperright[j][1] is upperright[k][1])
          k++
        hoverelt_ur.push(upperright[j]) if not witness
        j++
      hoverelt.push(hoverelt_ur) #hover[[hoverelt1],..],[hoverelt1] = [[h_ul],[h_ur]...],[h_ul] = [[pt_x,pt_y],..,[pt_X,pt_Y]]

      lowerright.sort (a,b) ->
        return if (a[1]<b[1] or (a[1] is b[1] and a[0]>b[0])) then -1 else 1
      hoverelt_lr = [] 
      j = 0
      while j < l #compare horizontally
        witness = false #witness is false if j'th elt can fill in
        k = 0
        while k < j and not witness
          witness = true if (lowerright[j][1] is lowerright[k][1])
          k++
        k = j+1
        while k < l and not witness
          witness = true if (lowerright[j][0] <= lowerright[k][0])
          k++
        hoverelt_lr.push(lowerright[j]) if not witness
        j++
      hoverelt.push(hoverelt_lr) #hover[[hoverelt1],..],[hoverelt1] = [[h_ul],...],[h_ul] = [[pt_x,pt_y],..,[pt_X,pt_Y]]

      lowerleft.sort (a,b) ->
        return if (a[1]<b[1] or (a[1] is b[1] and a[0]<b[0])) then -1 else 1
      hoverelt_ll = [] 
      j = 0
      while j < l #compare horizontally
        witness = false #witness is false if j'th elt can fill in
        k = 0
        while k < j and not witness
          witness = true if (lowerleft[j][1] is lowerleft[k][1])
          k++
        k = j+1
        while k < l and not witness
          witness = true if (lowerleft[j][0] >= lowerleft[k][0])
          k++
        hoverelt_ll.push(lowerleft[j]) if not witness
        j++
      hoverelt.push(hoverelt_ll) 

      upperleft.sort (a,b) ->
        return if (a[1]<b[1] or (a[1] is b[1] and a[0]>b[0])) then -1 else 1
      hoverelt_ul = [] #it will have points [[ul1],[ul2],...], [ul1] = [left,top]
      #begin fill in hoverelt_ul, need upper left most points
      j = 0
      while j < l #compare horizontally
        witness = false #witness is false if j'th elt can fill in
        k = 0
        while k < j and not witness
          witness = true if (upperleft[j][0]>= upperleft[k][0])
          k++
        k = j+1
        while k < l and not witness
          witness = true if (upperleft[j][1] is upperleft[k][1])
          k++
        hoverelt_ul.push(upperleft[j]) if not witness
        j++
      hoverelt.push(hoverelt_ul) 

      @_hover.push(_.clone(hoverelt)) #hover[[hoverelt1],..],[hoverelt1] = [[h_ul],...],[h_ul] = [[pt_x,pt_y],..,[pt_X,pt_Y]]
      i++


    #4-16-14
    #@_hover = temp2



    return  # Don't return the result of the for loop

  _drawHover: =>
    context = @_highlightsCanvas.getContext('2d')

    # Style used in variables.styl as well, keep it in sync
    # TODO: Ignoring rounded 2px border radius, implement

    context.save()

    context.lineWidth = 1
    # TODO: Colors do not really look the same if they are same as style in variables.styl, why?
    context.strokeStyle = 'rgba(180,170,0,9)'

    #4-16-14 elements in hover has the form (square, combined), where separated is boolean, combined=false means beginning a new part, need improvement, two lines are not separated, closed terms are not merged
    #@_hover[0][1] = false
    #l = @_hover.length
    #context.beginPath()
    #i = 0
    #while i < l 
    #  if not @_hover[i][1] # i is the beginning element of a part
    #    context.moveTo(@_hover[i][0].left,@_hover[i][0].top)
    #    context.lineTo(@_hover[i][0].left+@_hover[i][0].width,@_hover[i][0].top)
    #    j = i                                            #j iterate through the whole part
    #    while j < l and ((@_hover[j][1] and j isnt i) or (j is i))                #draw right half
    #      if j isnt l-1
    #        current = @_hover[j][0]
    #        currentleft = current.left
    #        currentright = current.left+current.width
    #        currenttop = current.top
    #        currentbottom = current.top+current.height        
    #        compare = @_hover[j+1][0]
    #        compareleft = compare.left
    #        compareright = compare.left+compare.width
    #        comparetop = compare.top
    #        comparebottom = compare.top+compare.height
    #        if (((comparetop-currentbottom <=5) and (comparetop-currentbottom >=-1)) or ((currenttop<=comparetop+2) and (comparetop<=currentbottom+2) and (currentbottom<=comparebottom+2))) and ((not (currentleft-compareright>15)) and (not (compareleft-currentright>15))) #ready to merge
    #          context.lineTo(currentright,comparetop)
    #          context.lineTo(compareright,comparetop)
    #        else 
    #          context.lineTo(currentright,currenttop)
    #          context.lineTo(currentright,currentbottom)
    #          @_hover[j+1][1] = false
    #      else 
    #        context.lineTo(@_hover[j][0].left+@_hover[j][0].width,@_hover[j][0].top+@_hover[j][0].height)
    #      j++
    #    j--
    #    while j>=i                                                        #draw left half
    #      current = @_hover[j][0]
    #      currentleft = current.left
    #      currentright = current.left+current.width
    #      currenttop = current.top
    #      currentbottom = current.top+current.height        
    #      context.lineTo(currentleft, currentbottom)  #can improve
    #      context.lineTo(currentleft, currenttop)
    #      j--
    #  i++
    #context.closePath()

    #4-23-14
    L = @_hover.length
    context.beginPath()
    i = 0
    while i< L
      hoverelt = _.clone(@_hover[i])
      upperright = hoverelt[0]
      console.log hoverelt
      lowerright = hoverelt[1]
      lowerleft = hoverelt[2]
      upperleft = hoverelt[3]
      context.moveTo(upperright[0][0],upperright[0][1])
      j = 0
      while j < (upperright.length-1)
        context.lineTo(upperright[j][0],upperright[j+1][1])
        context.lineTo(upperright[j+1][0],upperright[j+1][1])
        j++
      j = 0
      while j < (lowerright.length-1)
        context.lineTo(lowerright[j][0],lowerright[j][1])
        context.lineTo(lowerright[j+1][0],lowerright[j][1])
        j++
      context.lineTo(lowerright[j][0],lowerright[j][1])
      j = (lowerleft.length-1)
      while j >0
        context.lineTo(lowerleft[j][0],lowerleft[j][1])
        context.lineTo(lowerleft[j][0],lowerleft[j-1][1])
        j--
      context.lineTo(lowerleft[j][0],lowerleft[j][1])
      j = (upperleft.length-1)
      while j > 0
        context.lineTo(upperleft[j][0],upperleft[j][1])
        context.lineTo(upperleft[j-1][0],upperleft[j][1])
        j--
      context.lineTo(upperleft[j][0],upperleft[j][1])
      context.lineTo(upperright[0][0],upperright[0][1])
      i++
    context.closePath()



    context.stroke()

    # As shadow is drawn both on inside and outside, we clear inside to give a nice 3D effect
    # context.clearRect @_hover.left, @_hover.top, @_hover.width, @_hover.height

    context.restore()

  _hideHover: =>
    context = @_highlightsCanvas.getContext('2d')
    context.clearRect 0, 0, @_highlightsCanvas.width, @_highlightsCanvas.height

    # We restore hovers for other highlights
    highlight._drawHover() for highlight in @anchor.annotator.getHighlights() when @pageIndex is highlight.pageIndex and highlight._$highlight.hasClass 'hovered'

  _sortHighlights: =>
    @_$highlightsLayer.find('.highlights-layer-highlight').detach().sort(
      (a, b) =>
        # Heuristics, we put smaller highlights later in DOM tree which means they will have higher z-index
        # The motivation here is that we want higher the highlight which leaves more area to the user to select the other highlight by not covering it
        # TODO: Should we improve here? For example, compare size of (A-B) and size of (B-A), where A-B is A with (A intersection B) removed
        $(b).data('highlight')._area - $(a).data('highlight')._area
    ).appendTo(@_$highlightsLayer)

  _showControl: =>
    $control = @_$highlightsControl.find('.meta-menu')

    return if $control.is(':visible')

    $control.css(
      left: @_box.left + @_box.width + 1 # + 1 to not overlap border
      top: @_box.top - 2 # - 1 to align with fake border we style
    ).on(
      'mouseover.highlight mouseout.highlight': @_hoverHandler
      'mouseenter-highlight': @_mouseenterHandler
      'mouseleave-highlight': @_mouseleaveHandler
    )

    # TODO: Make reactive content of the template?
    $control.find('.meta-content').html(Template.highlightsControl @annotation).find('.delete').on 'click.highlight', (e) =>
      @anchor.annotator._removeHighlight @annotation._id

      return # Make sure CoffeeScript does not return anything

    $control.show()

  _hideControl: =>
    $control = @_$highlightsControl.find('.meta-menu')

    return unless $control.is(':visible')

    $control.hide().off(
      'mouseover.highlight mouseout.highlight': @_hoverHandler
      'mouseenter-highlight': @_mouseenterHandler
      'mouseleave-highlight': @_mouseleaveHandler
    )
    @_$highlightsControl.find('.meta-menu .meta-content .delete').off '.highlight'

  _clickHandler: (e) =>
    @anchor.annotator._selectHighlight @annotation._id

    return # Make sure CoffeeScript does not return anything

  # We process mouseover and mouseout manually to trigger custom mouseenter and mouseleave events.
  # The difference is that we do $.contains($highlightAndControl, related) instead of $.contains(target, related).
  # We check if related is a child of highlight or control, and not checking only for one of those.
  # This is necessary so that mouseleave event is not made when user moves mouse from a highlight
  # to a control. jQuery's mouseleave is made because target is not the same as $highlightAndControl.
  _hoverHandler: (e) =>
    $highlightAndControl = @_$highlight.add(@_$highlightsControl)

    target = e.target
    related = e.relatedTarget

    # No relatedTarget if the mouse left/entered the browser window
    if not related or (not $highlightAndControl.is(related) and not $highlightAndControl.has(related).length)
      if e.type is 'mouseover'
        e.type = 'mouseenter-highlight'
        $(target).trigger e
        e.type = 'mouseover'
      else if e.type is 'mouseout'
        e.type = 'mouseleave-highlight'
        $(target).trigger e
        e.type = 'mouseout'

  _mouseenterHandler: (e) =>
    @_mouseHovering = true

    @hover false
    return # Make sure CoffeeScript does not return anything

  _mouseleaveHandler: (e) =>
    @_mouseHovering = false

    if @_$highlight.hasClass 'selected'
      @_hideControl()
    else
      @unhover false

    return # Make sure CoffeeScript does not return anything

  hover: (noControl) =>
    # We have to check if highlight already is marked as hovered because of mouse events forwarding
    # we use, which makes the event be send twice, once when mouse really hovers the highlight, and
    # another time when user moves from a highlight to a control - in fact mouseover handler above
    # gets text layer as related target (instead of underlying highlight) so it makes a second event.
    # This would be complicated to solve, so it is easier to simply have this check here.
    if @_$highlight.hasClass 'hovered'
      # We do not do anything, but we still show control if it was not shown already
      @_showControl() unless noControl
      return

    @_$highlight.addClass 'hovered'
    @_drawHover()
    # When mouseenter handler is called by _annotationMouseenterHandler we do not want to show control
    @_showControl() unless noControl

    # We do not want to create a possible cycle, so trigger only if not called by _annotationMouseenterHandler
    $('.annotations-list .annotation').trigger 'highlightMouseenter', [@annotation._id] if noControl

  unhover: (noControl) =>
    # Probably not really necessary to check if highlight already marked as hovered but to match check above
    unless @_$highlight.hasClass 'hovered'
      # We do not do anything, but we still hide control if it was not hidden already
      @_hideControl() unless noControl
      return

    @_$highlight.removeClass 'hovered'
    @_hideHover()
    # When mouseleave handler is called by _annotationMouseleaveHandler we do not want to show control
    @_hideControl() unless noControl

    # We do not want to create a possible cycle, so trigger only if not called by _annotationMouseleaveHandler
    $('.annotations-list .annotation').trigger 'highlightMouseleave', [@annotation._id] if noControl

  _annotationMouseenterHandler: (e, annotationId) =>
    @hover true if annotationId in _.pluck @annotation.annotations, '_id'
    return # Make sure CoffeeScript does not return anything

  _annotationMouseleaveHandler: (e, annotationId) =>
    @unhover true if annotationId in _.pluck @annotation.annotations, '_id'
    return # Make sure CoffeeScript does not return anything

  _createHighlight: =>
    scrollLeft = $(window).scrollLeft()
    scrollTop = $(window).scrollTop()

    # We cannot simply use Range.getClientRects because it returns different
    # things in different browsers: in Firefox it seems to return almost precise
    # but a bit offset values (maybe just more testing would be needed), but in
    # Chrome it returns both text node and div node rects, so too many rects.
    # To assure cross browser compatibilty, we compute positions of text nodes
    # in a range manually.
    segments = for node in @normedRange.textNodes()
      $node = $(node)
      $wrap = $node.wrap('<span/>').parent()
      rect = $wrap.get(0).getBoundingClientRect()
      $node.unwrap()

      left: rect.left + scrollLeft - @_offset.left
      top: rect.top + scrollTop - @_offset.top
      width: rect.width
      height: rect.height

    @_computeArea segments
    @_boundingBox segments
    @_precomputeHover segments
    for segment in segments
      console.log segment
    @_$highlight = $('<div/>').addClass('highlights-layer-highlight').append(
      $('<div/>').addClass('highlights-layer-segment').css(segment) for segment in segments
    ).on
      'click.highlight': @_clickHandler
      'mouseover.highlight mouseout.highlight': @_hoverHandler
      'mouseenter-highlight': @_mouseenterHandler
      'mouseleave-highlight': @_mouseleaveHandler
      'annotationMouseenter': @_annotationMouseenterHandler
      'annotationMouseleave': @_annotationMouseleaveHandler

    @_$highlight.data 'highlight', @

    @_$highlightsLayer.append @_$highlight

    @_sortHighlights()

    # Annotator's anchors are realized (Annotator's highlight is created) when page is rendered
    # and virtualized (Annotator's highlight is destroyed) when page is removed. This mostly happens
    # as user scrolls around. But we want that if our highlight (Annotator's annotation) is selected
    # (selectedAnnotationId is set) when it is realized, it is drawn as selected and also that it is
    # really selected in the browser as a selection. So we do this here.
    @select() if @anchor.annotator.selectedAnnotationId is @annotation._id

  # React to changes in the underlying annotation
  annotationUpdated: =>
    # TODO: What to do when it is updated? Can we plug in reactivity somehow? To update template automatically?
    #console.log "In HL", @, "annotation has been updated."

  # Remove all traces of this highlight from the document
  removeFromDocument: =>
    # When removing, first we have to deselect it and just then remove it, otherwise
    # if this particular highlight is created again browser reselection does not
    # work (tested in Chrome). It seems if you have a selection and remove DOM
    # of text which is selected and then put DOM back and try to select it again,
    # nothing happens, no new browser selection is made. So what was happening
    # was that if you had a highlight selected on the first page (including
    # browser selection of the text in the highlight) and you scroll away so that
    # page was removed and then scroll back for page to be rendered again and
    # highlight realized (created) again, _createHighlight correctly called select
    # on the highlight, all CSS classes were correctly applied (making highlight
    # transparent), but browser selection was not made on text. If we deselect
    # when removing, then reselecting works correctly.
    @deselect() if @anchor.annotator.selectedAnnotationId is @annotation._id

    # We fake mouse leaving if highlight was hovered by any chance
    # (this happens when you remove a highlight through a control).
    @_mouseleaveHandler null

    $(@_$highlight).remove()

  # Just a helper function to draw highlight selected and make it selected by the browser, use annotator._selectHighlight to select
  select: =>
    selection = window.getSelection()
    selection.addRange @normedRange.toRange()

    @_$textLayer.addClass 'highlight-selected'
    @_$highlight.addClass 'selected'

    # We also want that selected annotations display a hover effect
    @hover true

  # Just a helper function to draw highlight unselected and make it unselected by the browser, use annotator._selectHighlight to deselect
  deselect: =>
    # Mark this highlight as deselected
    @_$highlight.removeClass 'selected'

    # Deselect everything
    selection = window.getSelection()
    selection.removeAllRanges()

    # We will re-add it in highlight.select() if necessary
    $('.text-layer', @anchor.annotator.wrapper).removeClass 'highlight-selected'

    # And re-select highlights marked as selected
    highlight.select() for highlight in @anchor.annotator.getHighlights() when highlight.isSelected()

    # If mouse is not over the highlight we unhover
    @unhover true unless @_mouseHovering

  # Is highlight currently drawn as selected, use annotator.selectedAnnotationId to get ID of a selected annotation
  isSelected: =>
    @_$highlight.hasClass 'selected'

  in: (clientX, clientY) =>
    @_$highlight.find('.highlights-layer-segment').is (i) ->
      # @ (this) is here a segment, DOM element
      rect = @.getBoundingClientRect()

      rect.left <= clientX <= rect.right and rect.top <= clientY <= rect.bottom

  # Get the HTML elements making up the highlight
  _getDOMElements: =>
    @_$highlight

  # Get bounding box with coordinates relative to the outer bounds of the display wrapper
  getBoundingBox: =>
    wrapperOffset = @anchor.annotator.wrapper.outerOffset()

    left: @_box.left + @_offset.left - wrapperOffset.left
    top: @_box.top + @_offset.top - wrapperOffset.top
    width: @_box.width
    height: @_box.height

class Annotator.Plugin.TextHighlights extends Annotator.Plugin
  pluginInit: =>
    Annotator.TextHighlight = PDFTextHighlight

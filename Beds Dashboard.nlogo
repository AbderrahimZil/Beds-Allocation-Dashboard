extensions [nw csv table]
;undirected-link-breed [ undirected-edges undirected-edge ]
breed [ beds bed ]
breed [ departments department ]
breed [circles circle]
breed [sides side]
departments-own [idp nber] ;; add features here
links-own [idl]

beds-own [
  idb
  idr
  utilization
  shared
  depts
  ] ;; add features here

globals [
  selected1
  current-state
  select-x
  select-y
  drag-x
  drag-y
  selected
  data
  p
  solution
  average-utilization
  highlighted-node                ; used for the "highlight mode" buttons to keep track of the currently highlighted node
  highlight-bicomponents-on       ; indicates that highlight-bicomponents mode is active
  stop-highlight-bicomponents     ; indicates that highlight-bicomponents mode needs to stop
  highlight-maximal-cliques-on    ; indicates highlight-maximal-cliques mode is active
  stop-highlight-maximal-cliques  ; indicates highlight-maximal-cliques mode needs to stop
]

to-report room [x]
  let q 0
  ask beds with [idb = x] [
    set q [idr] of self]
  report q
end

to movenode
  ifelse mouse-down? [
    ; if the mouse is down then handle selecting and dragging
    handle-select-and-drag
  ][
    set selected1 nobody
    reset-perspective
  ]
  display ; update the display
end

to handle-select-and-drag
  ; if no turtle is selected1
  ifelse selected1 = nobody  [
    set selected1 one-of beds with [round (xcor - mouse-xcor) = 0]
  ][
    ; if a turtle is selected1, move it to the mouse
    ask selected1 [ setxy mouse-xcor mouse-ycor ]
  ]
end

to layout
  ;; the number 3 here is arbitrary; more repetitions slows down the
  ;; model, but too few gives poor layouts
  repeat 5 [
    ;; the more beds we have to fit into the same amount of space,
    ;; the smaller the inputs to layout-spring we'll need to use
    let factor sqrt count beds
    if factor = 0 [ set factor 1 ]
    ;; numbers here are arbitrarily chosen for pleasing appearance
    layout-spring beds links (1 / factor ) (7 / factor) (2 / factor)
    display  ;; for smooth animation
  ]
  ;; don't bump the edges of the world
  let x-offset max [xcor] of beds + min [xcor] of beds
  let y-offset max [ycor] of beds + min [ycor] of beds
  ;; big jumps look funny, so only adjust a little each time
  set x-offset limit-magnitude x-offset 0.1
  set y-offset limit-magnitude y-offset 0.1
  ask beds [ setxy (xcor - x-offset / 2) (ycor - y-offset / 2) ]
end

to load-facility-network
  file-close ;; close already open file
  ca
  ask patches [set pcolor black]
  set solution user-file
  reset-ticks


  if ( solution != false )
  [
    file-open solution
  ]
end

to make-bed [bi ri util ch dps]
  create-beds 1
  [
    set color blue
    set idb bi
    set idr ri
    fd 8
;    set label id
    set utilization util / 100
    set shared ch
    set depts dps
    set size 0.5 + ((util / 1000)  * 2 + 0.7)* ln sqrt (util + 0.5); / 4;* 1.1
    set shape "square"
  ]
end

to gofile
  if file-at-end? [ plot-bed-use  stop ] ; plot-bed-use plot-department-assign
  set data csv:from-row file-read-line
  let n length data
  let i item 0 data
  let ir item 1 data
  let ch item 3 data
  let u item 2 data
  let dps sublist data 4 n

  ;; make bed node
  make-bed i ir u ch dps
  tick
end

; Takes a centrality measure as a reporter task, runs it for all nodes
; and set labels, sizes and colors of beds to illustrate result
to centrality [ measure ]
  nw:set-context beds links
  ask beds [
    let res (runresult measure) ; run the task for the turtle
    ifelse is-number? res [
      set label precision res 2
      set size res ; this will be normalized later
    ]
    [ ; if the result is not a number, it is because eigenvector returned false (in the case of disconnected graphs
      set label res
      set size 1
    ]
  ]
  normalize-sizes-and-colors
end

; We want the size of the beds to reflect their centrality, but different measures
; give different ranges of size, so we normalize the sizes according to the formula
; below. We then use the normalized sizes to pick an appropriate color.
to normalize-sizes-and-colors
  if count beds > 0 [
    let sizes sort [ size ] of beds ; initial sizes in increasing order
    let delta last sizes - first sizes ; difference between biggest and smallest
    ifelse delta = 0 [ ; if they are all the same size
      ask beds [ set size 1 ]
    ]
    [ ; remap the size to a range between 0.5 and 2.5
      ask beds [ set size ((size - first sizes) / delta) * 2 + 0.5 ]
    ]
    ask beds [ set color scale-color red size 0 5 ] ; using a higher range max not to get too white...
  ]
end

to weak-component
  nw:set-context beds links
  color-clusters nw:weak-component-clusters
end

to connect-beds
  ask links [die]
  let s 0
  (foreach (range 1 15) [
    [x] ->
;    show dept-num x
    set s x
    let l connect-beds1 dept-num x
    ;show sort beds with [member? self l] type sort other beds with [member? self l]
    ask beds with [member? self l][create-links-with other beds with [member? self l][set idl num-dept x]]])
;  ask links [set idl dept-num s] ;; here i asked all links
end

to-report connect-beds1 [dept]
  let l []
  ask beds [
    if member? dept [depts] of self [set l fput self l]]
  report l
end

to connect-beds2 [i]
    let l connect-beds1 i
end

; Colorizes the biggest maximal clique in the graph, or a random one if there is more than one
to find-biggest-cliques
  nw:set-context beds links
  color-clusters nw:biggest-maximal-cliques
end

to highlight-maximal-cliques
  if stop-highlight-maximal-cliques = true [
    ; we're asked to stop - do so
    set stop-highlight-maximal-cliques false
    set highlight-maximal-cliques-on false
    stop
  ]
  set highlight-maximal-cliques-on true ; we're on!
  if highlight-bicomponents-on = true [
    ; if the other guy is on, he needs to stop
    set stop-highlight-bicomponents true
  ]

  if mouse-inside? [
    nw:set-context beds links
    highlight-clusters nw:maximal-cliques
  ]
  display
end

; Allows the user to mouse over different nodes and
; highlight all the clusters that this node is a part of
to highlight-clusters [ clusters ]
;  show sort clusters
  ; get the node with neighbors that is closest to the mouse
  let node min-one-of beds [ distancexy mouse-xcor mouse-ycor ]
  if node != nobody and node != highlighted-node [
    set highlighted-node node
    ; find all clusters the node is in and assign them different colors
    color-clusters filter [ cluster -> member? node cluster ] clusters
    ; highlight target node
    ask node [ set color black ]
  ]
end

; Allows the user to mouse over and highlight all bicomponents
to highlight-bicomponents

  if stop-highlight-bicomponents = true [
    ; we're asked to stop - do so
    set stop-highlight-bicomponents false
    set highlight-bicomponents-on false
    stop
  ]
  set highlight-bicomponents-on true ; we're on!
  if highlight-maximal-cliques-on = true [
    ; if the other guy is on, he needs to stop
    set stop-highlight-maximal-cliques true
  ]

  if mouse-inside? [
    nw:set-context beds links
    highlight-clusters nw:bicomponent-clusters
  ]
  display
end

to-report num-dept [dept]
  let c 0
  if dept = "Behavioral Health" [set c 1]
  if dept = "Cardiology"  [set c 2]
  if dept = "Dermatology"  [set c 3]
  if dept = "ENT" [set c 4]
  if dept ="Endocrinology"  [set c 5]
  if dept = "Family Medicine"  [set c 6]
  if dept ="Gastroenterology"  [set c 7]
  if dept ="Gynecology and Obstetrics"  [set c 8]
  if dept ="Neurology" [set c 9]
  if dept ="Oncology"  [set c 10]
  if dept ="Orthopedics"  [set c 11]
  if dept ="Podiatry"  [set c 12]
  if dept ="Pulmonary and Allergy"  [set c 13]
  if dept ="Urology"  [set c 14]
  report c
end

to-report dept-num [dept]
  report (ifelse-value
  dept = 1 ["Behavioral Health"]
  dept = 2 ["Cardiology"]
  dept = 3 ["Dermatology"]
  dept = 4 ["ENT"]
  dept = 5 ["Endocrinology"]
  dept = 6 ["Family Medicine"]
  dept = 7 ["Gastroenterology"]
  dept = 8 ["Gynecology and Obstetrics"]
  dept = 9 ["Neurology"]
  dept = 10 ["Oncology"]
  dept = 11 ["Orthopedics"]
  dept = 12 ["Podiatry"]
  dept = 13 ["Pulmonary and Allergy"]
  dept = 14 ["Urology"]
    )
end

to community-detection
  nw:set-context beds links
  color-clusters nw:louvain-communities
end

to color-clusters [ clusters ]
  ; reset all colors
  ask beds [ set color gray - 3  set label ""]
  ask links [ set color gray - 3 ]
  let n length clusters
  let colors ifelse-value (n <= 12)
    [ n-of n remove gray remove white base-colors ] ;; choose base colors other than white and gray
    [ n-values n [ approximate-hsb (random 255) (255) (100 + random 100) ] ] ; too many colors - pick random ones
    ; loop through the clusters and colors zipped together
    (foreach clusters colors [ [cluster cluster-color] ->
      ask cluster [ ; for each node in the cluster
        ; give the node the color of its cluster
        set color cluster-color
      set label idr
      set average-utilization mean([utilization] of beds with [color = cluster-color])

        ; colorize the links from the node to other nodes in the same cluster
        ; link color is slightly darker...
        ask my-links [ if member? other-end cluster [ set color cluster-color - 1 ] ] ] ])
end

to inspect-turtle
  ifelse any? beds with [distancexy mouse-xcor mouse-ycor < 1] [
    ask min-one-of beds [distancexy mouse-xcor mouse-ycor] [
      set label utilization ;idr
;      ask other beds [set label "Hello"]
  ] ]
  [ ask beds [set label ""] ]
end

to go-inspect-turtle ;Set as a forever button
  if mouse-down? [inspect-turtle]
end
;
to layout-beds
  if playout = "radial" and count beds > 1 [
    let root-agent max-one-of beds [ count my-links ]
    layout-radial beds links root-agent
  ]
  if playout = "spring" [
    let fdepartment ln abs ln sqrt (1.2 * count beds + 0.01)
    if fdepartment = 0 [ set fdepartment 1.1 ]
    layout-spring beds links (1 / fdepartment) (14 / fdepartment) (3 / fdepartment)
;    layout-spring beds links (1 / fdepartment ) (7 / fdepartment) (2 / fdepartment)
      ;; don't bump the edges of the world
;    let x-offset max [xcor] of beds + min [xcor] of beds
;    let y-offset max [ycor] of beds + min [ycor] of beds
;    ;; big jumps look funny, so only adjust a little each time
;    set x-offset limit-magnitude x-offset 0.6
;    set y-offset limit-magnitude y-offset 0.6
;    ask beds [ setxy (xcor - x-offset / 2) (ycor - y-offset / 2) ]
  ]
  if playout = "circle" [
    layout-circle sort beds max-pxcor * 0.9
  ]
  if playout = "tutte" [
    layout-circle sort beds max-pxcor * 0.9
    layout-tutte max-n-of (count beds * 0.5) beds [ count my-links ] links 12
  ]
  display
end

;; for beds
to plot-bed-use
  ;; Define plot variables:
  let y.a sort [idb] of beds ;(item 0 [idr] of beds) 6 7 ;; substring Rid 5 7
;  show y.a
;  let y.b [use] of beds
  let y.b map [ i -> item 0 [utilization] of beds with [idb = i]] y.a

  let plotname "Utilization Of Beds"
  let ydata (list y.b)
  let xdata (list y.a)
  let pencols (list 56) ; green 16
  let barwidth 0.2
  let step 1
;  type "beds "
;  show xdata
  ;; Call the plotting procedure
  groupedbarplotbeds plotname ydata xdata pencols barwidth step ; xdata
end

to groupedbarplotbeds [plotname ydata xdata pencols barwidth step]
  ;; Get n from ydata -> number of groups (colors)
  let n length ydata
  let i 0
  ;; Loop over ydata groups (colors)
  while [i < n]
  [
    let y item i ydata
    let x item i xdata
;    let x (range 1 73) ;; plot also for 0 used beds ;    let x n-values (length y) [? -> (i * barwidth) + (? * (((n + 1) * barwidth)))]
;    print x
;    print y
    ;; Initialize the plot (create a pen, set the color, set to bar mode and set plot-pen interval)
    set-current-plot plotname
    set-plot-x-range 1 73 ;cuz data from 1 to 72
    create-temporary-plot-pen (word i)
    set-plot-pen-color item i pencols
    set-plot-pen-mode 1
    set-plot-pen-interval step

    ;; Loop over xy values from the two lists:
    let j 0
    while [j < length x]
    [ let x.temp item j x
      let x.max x.temp + (barwidth * 0.97)
      let y.temp item j y
      ;; Loop over x-> xmax and plot repeatedly with increasing x.temp to create a filled barplot
      while [x.temp < x.max]
      [
        plotxy x.temp y.temp
        set x.temp (x.temp + step)
      ] ;; End of x->xmax loop
      set j (j + 1)
    ] ;; End of dataloop for current group (i)
    set i (i + 1)
  ] ;; End of loop over all groups
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Centrality Measures
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to betweenness
  centrality [ -> nw:betweenness-centrality ]
end

to eigenvector
  centrality [ -> nw:eigenvector-centrality ]
end

to closeness
  centrality [ -> nw:closeness-centrality ]
end

to-report limit-magnitude [number limit]
  if number > limit [ report limit ]
  if number < (- limit) [ report (- limit) ]
  report number
end

to Matrix
;  clear-all
  nw:set-context beds links
  nw:save-matrix "matrix.txt"
end

to Graph
  clear-all
  nw:load-matrix "matrix.txt" beds links
  if layout? [ layout ]
end

; A good portion of this analysis is from Uri Wilensky code.
@#$#@#$#@
GRAPHICS-WINDOW
947
10
1713
777
-1
-1
8.33
1
10
1
1
1
0
0
0
1
-45
45
-45
45
1
1
1
ticks
60.0

SWITCH
792
342
938
375
plot?
plot?
0
1
-1000

SWITCH
792
377
938
410
layout?
layout?
0
1
-1000

MONITOR
757
241
836
286
# links
count links
3
1
11

BUTTON
219
524
385
607
layout
layout-beds
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
49
524
216
607
Load Beds Network
load-facility-network\n;gofile
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
49
612
168
744
Build Network
gofile\n;ask beds [set label idr]
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
683
241
752
286
# beds
count beds
17
1
11

BUTTON
427
672
561
744
communities
community-detection
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
172
661
385
745
Connect beds
connect-beds
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
564
525
729
583
biggest clique
find-biggest-cliques
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
565
588
729
629
NIL
highlight-maximal-cliques
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
564
635
729
668
NIL
find-biggest-cliques
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
564
674
730
707
NIL
highlight-bicomponents
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
565
711
730
744
NIL
weak-component
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
426
525
561
583
NIL
betweenness
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
427
588
561
623
NIL
eigenvector
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
427
629
560
665
NIL
closeness
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
12
12
943
178
Utilization Of Beds
bed #
%
0.0
10.0
0.0
1.0
true
false
"" ""
PENS

MONITOR
840
241
939
286
# emptybeds
count beds with [shared = 0]
17
1
11

INPUTBOX
772
525
911
594
look-for-bed
70.0
1
0
Number

BUTTON
773
597
912
743
look for bed
ifelse p != look-for-bed\n[\nask beds [set color blue set label \"\"]\nask beds with [ idb = look-for-bed ]\n[set color green\nset label idr ]\nset p look-for-bed] \n[set p look-for-bed]
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
820
291
939
336
Utilization of Bed
[utilization] of highlighted-node
17
1
11

MONITOR
683
291
814
336
Average Utilization
average-utilization
17
1
11

TEXTBOX
63
186
166
204
Section 1
11
0.0
1

TEXTBOX
215
185
280
203
Section 2
11
0.0
1

TEXTBOX
526
185
595
203
Section 4
11
0.0
1

TEXTBOX
360
184
446
202
Section 3
11
0.0
1

TEXTBOX
666
186
758
204
Section 5
11
0.0
1

TEXTBOX
820
187
906
205
Section 6
11
0.0
1

CHOOSER
172
613
384
658
playout
playout
"radial" "tutte" "spring"
2

@#$#@#$#@
## WHAT IS IT?

In some networks, a few "hubs" have lots of connections, while everybody else only has a few.  This model shows one way such networks can arise.

Such networks can be found in a surprisingly large range of real world situations, ranging from the connections between websites to the collaborations between actors.

This model generates these networks by a process of "preferential attachment", in which new network members prefer to make a connection to the more popular existing members.

## HOW IT WORKS

The model starts with two nodes connected by an edge.

At each step, a new node is added.  A new node picks an existing node to connect to randomly, but with some bias.  More specifically, a node's chance of being selected is directly proportional to the number of connections it already has, or its "degree." This is the mechanism which is called "preferential attachment."

## HOW TO USE IT

Pressing the GO ONCE button adds one new node.  To continuously add nodes, press GO.

The LAYOUT? switch controls whether or not the layout procedure is run.  This procedure attempts to move the nodes around to make the structure of the network easier to see.

The PLOT? switch turns off the plots which speeds up the model.

The RESIZE-NODES button will make all of the nodes take on a size representative of their degree distribution.  If you press it again the nodes will return to equal size.

If you want the model to run faster, you can turn off the LAYOUT? and PLOT? switches and/or freeze the view (using the on/off button in the control strip over the view). The LAYOUT? switch has the greatest effect on the speed of the model.

If you have LAYOUT? switched off, and then want the network to have a more appealing layout, press the REDO-LAYOUT button which will run the layout-step procedure until you press the button again. You can press REDO-LAYOUT at any time even if you had LAYOUT? switched on and it will try to make the network easier to see.

## THINGS TO NOTICE

The networks that result from running this model are often called "scale-free" or "power law" networks. These are networks in which the distribution of the number of connections of each node is not a normal distribution --- instead it follows what is a called a power law distribution.  Power law distributions are different from normal distributions in that they do not have a peak at the average, and they are more likely to contain extreme values (see Albert & Barabási 2002 for a further description of the frequency and significance of scale-free networks).  Barabási and Albert originally described this mechanism for creating networks, but there are other mechanisms of creating scale-free networks and so the networks created by the mechanism implemented in this model are referred to as Barabási scale-free networks.

You can see the degree distribution of the network in this model by looking at the plots. The top plot is a histogram of the degree of each node.  The bottom plot shows the same data, but both axes are on a logarithmic scale.  When degree distribution follows a power law, it appears as a straight line on the log-log plot.  One simple way to think about power laws is that if there is one node with a degree distribution of 1000, then there will be ten nodes with a degree distribution of 100, and 100 nodes with a degree distribution of 10.

## THINGS TO TRY

Let the model run a little while.  How many nodes are "hubs", that is, have many connections?  How many have only a few?  Does some low degree node ever become a hub?  How often?

Turn off the LAYOUT? switch and freeze the view to speed up the model, then allow a large network to form.  What is the shape of the histogram in the top plot?  What do you see in log-log plot? Notice that the log-log plot is only a straight line for a limited range of values.  Why is this?  Does the degree to which the log-log plot resembles a straight line grow as you add more nodes to the network?

## EXTENDING THE MODEL

Assign an additional attribute to each node.  Make the probability of attachment depend on this new attribute as well as on degree.  (A bias slider could control how much the attribute influences the decision.)

Can the layout algorithm be improved?  Perhaps nodes from different hubs could repel each other more strongly than nodes from the same hub, in order to encourage the hubs to be physically separate in the layout.

## NETWORK CONCEPTS

There are many ways to graphically display networks.  This model uses a common "spring" method where the movement of a node at each time step is the net result of "spring" forces that pulls connected nodes together and repulsion forces that push all the nodes away from each other.  This code is in the `layout-step` procedure. You can force this code to execute any time by pressing the REDO LAYOUT button, and pressing it again when you are happy with the layout.

## NETLOGO FEATURES

Nodes are turtle agents and edges are link agents. The model uses the ONE-OF primitive to chose a random link and the BOTH-ENDS primitive to select the two nodes attached to that link.

The `layout-spring` primitive places the nodes, as if the edges are springs and the nodes are repelling each other.

Though it is not used in this model, there exists a network extension for NetLogo that comes bundled with NetLogo, that has many more network primitives.

## RELATED MODELS

See other models in the Networks section of the Models Library, such as Giant Component.

See also Network Example, in the Code Examples section.

## CREDITS AND REFERENCES

This model is based on:
Albert-László Barabási. Linked: The New Science of Networks, Perseus Publishing, Cambridge, Massachusetts, pages 79-92.

For a more technical treatment, see:
Albert-László Barabási & Reka Albert. Emergence of Scaling in Random Networks, Science, Vol 286, Issue 5439, 15 October 1999, pages 509-512.

Barabási's webpage has additional information at: http://www.barabasi.com/

The layout algorithm is based on the Fruchterman-Reingold layout algorithm.  More information about this algorithm can be obtained at: http://cs.brown.edu/people/rtamassi/gdhandbook/chapters/force-directed.pdf.

For a model similar to the one described in the first suggested extension, please consult:
W. Brian Arthur, "Urban Systems and Historical Path-Dependence", Chapt. 4 in Urban systems and Infrastructure, J. Ausubel and R. Herman (eds.), National Academy of Sciences, Washington, D.C., 1988.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (2005).  NetLogo Preferential Attachment model.  http://ccl.northwestern.edu/netlogo/models/PreferentialAttachment.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2005 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

<!-- 2005 -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
set layout? false
set plot? false
setup repeat 300 [ go ]
repeat 100 [ layout ]
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@

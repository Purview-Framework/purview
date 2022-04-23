# Purview

A framework to build interactive UIs with Haskell.  It's inspired by Phoenix LiveView, React, and Redux + Sagas.

It's server side rendered and uses websockets to communicate HTML updates and to receive events.  State can be broken up into small components.  Events are captured by the state handlers, which can change the state, and in turn change the HTML.

The focus is on providing useful atoms while allowing users to really play with the framework.

It's still in early development so expect things to break or be missing!

## What it looks like

Here's what a component looks like (see `experiments/Counter.hs`):

```haskell

module Main where

import Prelude hiding (div)
import Data.Aeson
import Data.Aeson.TH

import Purview

data Direction = Up | Down

$(deriveJSON defaultOptions ''Direction)

upButton = onClick Up $ div [ text "up" ]
downButton = onClick Down $ div [ text "down" ]

handler = messageHandler (0 :: Int) reducer
  where
    reducer Up   state = (state + 1, [])
    reducer Down state = (state - 1, [])

counter state = div
  [ upButton
  , text $ "count: " <> show state
  , downButton
  ]

view = handler counter

main = Purview.run defaultConfiguration { component=view }
```

## Overview

### Adding attributes to HTML elements

Attributes flow down to concrete HTML.

For example, if you wanted to add a `style="color: blue;"` to a `div`:

``` haskell
blue = style "color: blue;"

blueDiv = blue (div [])
```

Calling `render blueDiv` will produce `<div style="color: blue;"></div>"`

If you wanted to have a blue div that's 50% of the width,

``` haskell
blue = style "color: blue;"
halfWidth = style "width: 50%;"

view = blue (halfWidth (div [])
```

Now `render view` will produce `<div style="color: blue; width: 50%;></div>`

As purview is non-prescriptive in what attributes you can give a `div`, or any other HTML element, you can create your own.

If you need `name` attribute put on `div`s or other HTML, you can do:

``` haskell
nameAttr = Attribute . Generic "name"

namedDiv = nameAttr "wumbo" (div [])
```

And `render namedDiv` will produce `<div name="wumbo"></div>`.  Eventually there will be more attributes-by-default like `style`, but for now expect to build up what you need!

### Creating new HTML elements

Just like you can add new attributes, you can also add new html elements.  For example, if you need a button

``` haskell
button = Html "button"

view = button [ text "click" ]
```

Now `render view` will produce `<button>click</button>`.  Like all the built in ones, attributes will flow down and be added to the button.

### Events

At the core of Purview are two event handlers, `messageHandler` and `effectHandler`.  The former is intended for pure functions, and the latter is for running effects.  Handling an event is run in its own green thread.

Handlers take an initial state and a reducer.  The reducer receives actions from anywhere below them in the tree, and returns the new state with a list of actions to send either to itself or up the tree to the parent.  The handler passes down the state to its child.  This is the core idea to make it all interactive.

For example, if we wanted to build something that fetched the server time on each click:

``` haskell
reducer action state = case action of
  "getTime" -> do
      time <- getCurrentTime
      pure (Just time, [])

handler = effectHandler Nothing reducer

view time = div 
  [ onClick "getTime" $ button [ text "check time" ]
  , p [ text (show time) ]
  ]
  
component = handler view
```

Some things to note:
* The state is passed down to children
* Events bubble up to the nearest handler where they are captured
* `onClick` can wrap anything -- like other attributes it flows down to concrete HTML
* The reducer is run in its own thread when an event is received, so you don't have to worry about slow operations locking the page

### Overview

Using the above example of getting the time, here's how events flow when the user clicks "check time"

```
     +------------------------------------+                                                                          
     | Browser                            |                                                                          
+--->|                                    |                                                                          
|    | +------------------------+         |                                                                          
|    | |User clicks "check time"|         |                                                                          
|    | +------------------------+         |                                                                          
|    +----|-------------------------------+                                                                          
|         |                                                                                                          
|         | { "event": "click", "location": "[0]", message: "checkTime" }                                            
|         |                                                                                                          
|         |                                                                                                          
|         |                                                                                                          
|         |                                                                                                          
|         |                                   { "event": "newState", "location": "[0]", message: "Just 2:29pm" }     
|         |        +---------------------------------------------------------+                                       
|         v        v                                                         |                                       
|    +-------------------------------------+                                 |                                       
|    | Event Loop                          |                                 |                                       
|    |                                     |            +-----------------------------------------+                   
|    | +---------------------------------+ |            | Green Thread                            |                   
|    | |Handler is identified by location|------------->|                                         |                   
|    | +---------------------------------+ |            | Handler is run and creates state change |                   
|    |                                     |            +-----------------------------------------+                   
|    | +--------------------------+        |                                                                         
|    | |State change produces diff|        |                                                                         
|    | +--------------------------+        |                                                                         
|    +---|---------------------------------+                                                                         
|        |                                                                                                           
+--------+                                                                                                           
     { "event": "setHtml", "message": [{ location: [0], html: "<p>Just 2:20pm</p>" }] }                              

```


### Contributing

Anything is welcome, including examples or patterns you found nice.  Since Purview is mostly focused on providing atoms to make building things possible, there's a lot to discover and talk about.

### Installation

1. Install [stack](https://docs.haskellstack.org/en/stable/README/)
2. `stack build`
3. `stack exec purview-exe` for just running the example above
4. `stack exec purview` for the ~ experimental ~ and not-currently working repl

### Running Tests

1. The same as above with stack and build
2. `stack test`

/******************************************************************************
* Playing Card Objects                                                        *
*                                                                             *
* Do not remove this notice.                                                  *
*                                                                             *
* Copyright 2001 by Mike Hall                                                 *
* Please see http://www.brainjar.com for terms of use.                        *
******************************************************************************/

//=============================================================================
// Card Object
//
// Note: Requires cards.css for display.
//=============================================================================

//-----------------------------------------------------------------------------
// Card constructor function.
//-----------------------------------------------------------------------------

function Card(rank, suit) {
  // Small correction for the single char ranks
  if (rank === 'T') {
      rank = '10';
  }

  this.rank = rank;
  this.suit = suit;

  this.toString   = cardToString;
  this.createNode = cardCreateNode;
}

//-----------------------------------------------------------------------------
// cardToString(): Returns the name of a card (including rank and suit) as a
// text string.
//-----------------------------------------------------------------------------

function cardToString() {

  var rank, suit;

  switch (this.rank) {
    case "A" :
      rank = "Ace";
      break;
    case "2" :
      rank = "Two";
      break;
    case "3" :
      rank = "Three";
      break;
    case "4" :
      rank = "Four";
      break;
    case "5" :
      rank = "Five";
      break;
    case "6" :
      rank = "Six";
      break;
    case "7" :
      rank = "Seven";
      break;
    case "8" :
      rank = "Eight";
      break;
    case "9" :
      rank = "Nine";
      break;
    case "10" :
      rank = "Ten";
      break;
    case "J" :
      rank = "Jack"
      break;
    case "Q" :
      rank = "Queen"
      break;
    case "K" :
      rank = "King"
      break;
    default :
      rank = null;
      break;
  }

  switch (this.suit) {
    case "C" :
      suit = "Clubs";
      break;
    case "D" :
      suit = "Diamonds"
      break;
    case "H" :
      suit = "Hearts"
      break;
    case "S" :
      suit = "Spades"
      break;
    default :
      suit = null;
      break;
  }

  if (rank == null || suit == null)
    return "";

  return rank + " of " + suit;
}

//-----------------------------------------------------------------------------
// cardCreateNode(): Returns a DIV node which can be used to display the card 
// on a page.
//-----------------------------------------------------------------------------

var cardImg0 = new Image(); cardImg0.src= "graphics/cardback.gif";
var cardImg1 = new Image(); cardImg1.src= "graphics/jack.gif";
var cardImg2 = new Image(); cardImg2.src= "graphics/queen.gif";
var cardImg3 = new Image(); cardImg3.src= "graphics/king.gif";

function cardCreateNode() {

  var cardNode, frontNode, indexNode, spotNode, tempNode, textNode;
  var indexStr, spotChar;

  // This is the main node, a DIV tag.

  cardNode = document.createElement("DIV");
  cardNode.className = "card";

  // Build the front of card.

  frontNode = document.createElement("DIV");
  frontNode.className = "front";

  // Get proper character for card suit and change font color if necessary.

  spotChar = "\u00a0";
  switch (this.suit) {
    case "C" :
      spotChar = "\u2663";
      break;
    case "D" :
      frontNode.className += " red";
      spotChar = "\u2666";
      break;
    case "H" :
      frontNode.className += " red";
      spotChar = "\u2665";
      break;
    case "S" :
      spotChar = "\u2660";
      break;
  }

  // Create and add the index (rank) to the upper-left corner of the card.

  indexStr = this.rank;
  if (this.toString() == "")
    indexStr = "\u00a0";
  spotNode = document.createElement("DIV");
  spotNode.className = "index";
  textNode = document.createTextNode(indexStr);
  spotNode.appendChild(textNode);
  spotNode.appendChild(document.createElement("BR"));
  textNode = document.createTextNode(spotChar);
  spotNode.appendChild(textNode);
  frontNode.appendChild(spotNode);


  // Create and add the index (rank) to the bottom-right corner of the card.
  spotNode2 = document.createElement("DIV");
  spotNode2.style.transform = "rotateZ(180deg)"
  spotNode2.className = "index_bottom";
  textNode2 = document.createTextNode(indexStr);
  spotNode2.appendChild(textNode2);
  spotNode2.appendChild(document.createElement("BR"));
  textNode2 = document.createTextNode(spotChar);
  spotNode2.appendChild(textNode2);
  frontNode.appendChild(spotNode2);

  // Create and add spots based on card rank (Ace thru 10).

  spotNode = document.createElement("DIV");
  textNode = document.createTextNode(spotChar);
  spotNode.appendChild(textNode);
  if (this.rank == "A") {
    spotNode.className = "ace";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "3" || this.rank == "5" || this.rank == "9") {
    spotNode.className = "spotB3";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "2" || this.rank == "3") {
    spotNode.className = "spotB1";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "2" || this.rank == "3") {
    spotNode.className = "spotB5";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "4" || this.rank == "5" || this.rank == "6" ||
      this.rank == "7" || this.rank == "8" || this.rank == "9" ||
      this.rank == "10") {
    spotNode.className = "spotA1";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotA5";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC1";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC5";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "6" || this.rank == "7" || this.rank == "8") {
    spotNode.className = "spotA3";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC3";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "7" || this.rank == "8" || this.rank == "10") {
    spotNode.className = "spotB2";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "8" || this.rank == "10") {
    spotNode.className = "spotB4";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }
  if (this.rank == "9" || this.rank == "10") {
    spotNode.className = "spotA2";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotA4";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC2";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC4";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }

  // For face cards (Jack, Queen or King), create and add the proper image.

  tempNode = document.createElement("IMG");
  tempNode.className = "face";
  if (this.rank == "J")
    tempNode.src = "graphics/jack.gif";
  if (this.rank == "Q")
    tempNode.src = "graphics/queen.gif";
  if (this.rank == "K")
    tempNode.src = "graphics/king.gif";

  // For face cards, add suit characters to the upper-left and lower-right
  // corners.

  if (this.rank == "J" || this.rank == "Q" || this.rank == "K") {
    frontNode.appendChild(tempNode);
    spotNode.className = "spotA1";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
    spotNode.className = "spotC5";
    tempNode = spotNode.cloneNode(true);
    frontNode.appendChild(tempNode);
  }

  // Add front node to the card node.

  cardNode.appendChild(frontNode);

  // Return the card node.

  return cardNode;
}

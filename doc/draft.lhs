\documentclass[preprint, 9pt]{sigplanconf}

%include polycode.fmt

\usepackage{amsmath}
\usepackage{amssymb}
\usepackage{url}
\usepackage{pgf}
\usepackage{pdfpages}
\usepackage{booktabs}
\usepackage[numbers]{natbib}  % For URLs in bibliography
\usepackage{subfigure}
\usepackage{color}
% \usepackage{caption}
% \usepackage{subcaption}

\newcommand{\ra}[1]{\renewcommand{\arraystretch}{#1}}
% Used to hide Haskell code from LaTeX
\long\def\ignore#1{}

% General formatting directives/macros
%format subst (term) (v) (e) = [v "\mapsto" e] term
%format ^ = "\mathbin{\char`\^}"
%format a1 = "a_1"
%format a2 = "a_2"
%format c1 = "c_1"
%format c2 = "c_2"
%format e1 = "e_1"
%format e2 = "e_2"
%format a'1 = "a^{\prime}_1"
%format a'2 = "a^{\prime}_2"
%format e'1 = "e^{\prime}_1"
%format e'2 = "e^{\prime}_2"
%format forall (x) = "\mathopen{}\forall" x "\mathclose{}"
\def\commentbegin{\quad\{\ }
\def\commentend{\}}

% For typesetting infer rules, found in proof.sty in this directory
\usepackage{proof}
\usepackage{bussproofs}

% If we want white lines in a table
\newcommand{\whiteline}{\\[0.2in]}

\newcommand{\tom}[1]{\textcolor{red}{\textbf{[\textsc{Tom:} \textcolor{black}{#1}]}}}

% Document metadata

\conferenceinfo{WXYZ '05}{date, City.}
\copyrightyear{2005}
\copyrightdata{[to be supplied]}

% \titlebanner{banner above paper title}        % These are ignored unless
% \preprintfooter{short description of paper}   % 'preprint' option specified.

\title{Bringing Functions into the Fold}
% \subtitle{Subtitle Text, if any}

\authorinfo{Jasper Van der Jeugt \and Steven Keuchel \and Tom Schrijvers}{Ghent University, Belgium}{\{jasper.vanderjeugt,steven.keuchel,tom.schrijvers\}@@ugent.be}

\begin{document}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\maketitle

\ignore{
\begin{code}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Rank2Types      #-}
import Data.Char     (toUpper)
import Prelude       hiding (head, foldr, map, sum, replicate)
\end{code}
}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\begin{abstract}
Rewriting explicitly recursive functions in terms of higher-order functions such
as |fold| and |map| brings many advantages such as conciseness, improved
readability, and it facilitates some optimisations. However, it is not always
straightforward for a programmer to write functions in this style. We present an
approach to automatically detect these higher-order functions, so the programmer
can have his cake and eat it, too.
\end{abstract}

% TODO: Explicit results, evaluation

\category{CR-number}{subcategory}{third-level}

\terms
term1, term2

\keywords
paramorphisms, fold-build fusion, analysis, transformation 


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Introduction}

Higher-order functions are immensely popular in Haskell, whose Prelude alone
offers a wide range of them (e.g., |map|, |filter|, |any|, \ldots). This is not
surprising, because they the key \emph{abstraction} mechanism of functional
programming languages. They enable capturing and reusing common patterns among,
often recursive, function definitions to a much larger extent than first-order
functions. In addition to the obvious code reuse and increased programmer
productivity, uses of higher-order functions have many other potential
advantages over conventional first-order definitions.
\begin{itemize}
\item Uses of higher-order functions can be more quickly understood because
      they reduce the that is already known pattern to a single name and thus draw
      the attention immediately to what is new (i.e., the function parameters).

\item Because the code is more compact and the number of bugs is proportional
      to code size~\cite{gaffney1984}, higher-order functions should lead to
      fewer bugs.

\item Properties can be established for the higher-order function indepently
      from its particular uses. This makes (e.g., equational) reasoning more productive.

\item Since properties and occurrences are more readily available, they make good targets
      for automatic optimization in compilers.
\end{itemize}

A particularly ubiquitous pattern is that of folds or \emph{catamorphisms}. In
the case of lists, this pattern has been captured in the well-known |foldr|
function.
\begin{code}
foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ z []        = z
foldr f z (x : xs)  = f x (foldr f z xs)
\end{code}
Indeed, the research literature is full of applications,
properties and optimizations based on folds. \tom{add many citations}

Hence, given all these advantages of folds, one would expect every programmer
to diligently avoid explicit recursion where folds can do the job.
Unfortunately, that is far from true in practice. For many reasons, programmers
do not write their code in terms of explicit folds. This class comprises a
large set of advanced functional programmers \tom{evidence of our case study}.
This is compounded by the fact that programmers often do not bother to define
the equivalent of |foldr| for other inductive algebraic datatypes.

Yet, sadly, these first-order recursive functions are treated as second-class
by compilers. They do not benefit from the same performance gains like loop
fusion and deforestations. In fact, the leading Haskell compiler GHC won't even
inline recursive functions. We disagree with this injustice and argue that it
is quite unnecessary to penalize programmers for using first-class recursion.
In fact, we show that with a little effort, paramorphisms can be detected
automatically by the compiler and automatically transformed into explicit
invocations of folds for the purpose of automation.

In particular, our specific contribuations are:
\begin{enumerate}
\item We show how to automatically identify \emph{paramorphisms} and transform
      them into explicit calls to |fold|. 
\item In order to support a particular well-known optimization,
      fold-build fusion, we also show how to automatically detect and transform
      functions that can be expressed as a call to |build|.
\item We provide a GHC compiler plugin that performs these detections and
      transformations on GHC Core.
      It covers not only paramorphisms over Haskell lists, but paramorphisms
      over all inductively defined directly recursive datatypes.
\item We have performed a case study of our detection and transformation
      plugin on a range of well-known Haskell packages and applications
      to take stock of the number of explicitly recursive paramorphisms
      and currently missed opportunities for fold-build fusion.
      \tom{The results are astounding.}
\end{enumerate}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\newpage
\section{Overview}

% In the early days of computing, assembly code was used for writing programs. In
% assembly, the control flow of a program is controlled using \emph{jumps}. This
% convention was continued in early programming languages, and developers
% manipulated the control flow of their applications using the \texttt{goto}
% construct. This allowed \emph{arbitrary} jumps through code, which brought with
% it many disadvantages \cite{dijkstra1968}. In particular, it could be very hard
% to understand code written in this style.
% 
% Later programming languages favoured use of control stuctures such as
% \texttt{for} and \texttt{while} over \texttt{goto}. This made it easier for
% programmers and tools to reason about these structures.
% 
% For example, loop invariants can be used to reason about \texttt{while} loops:
% 
% \begin{center}
% \mbox{
%     \infer{
%         \left\{ I \right\} \text{while} (C) ~ \text{body}
%         \left\{ \lnot C \wedge I \right\}
%     }{
%         \left\{C \wedge I\right\} \text{body} \left\{ I \right\}
%     }
% }
% \end{center}
% 
% Additionally, \texttt{goto}-based code can be much harder to understand: the
% developer needs to understand the function in its entirety before arriving at a
% basic understanding of the control flow.
% 
% A similar argument can be made about \emph{explicit recursion} in functional
% programming languages. Consider the simple functions:

\subsection{Paramorphisms and Folds}
Paramorphisms are functions that perform structural recursion
over an inductively defined algebraic datatype. Here are two
examples of paramorphisms over the most ubiquitous inductive
datatype, lists.
\begin{code}
upper :: String -> String
upper []        = []
upper (x : xs)  = toUpper x : upper xs

sum :: [Int] -> Int
sum []        = 0
sum (x : xs)  = x + sum xs
\end{code}

% Explicit recursion is used in both functions to iterate over a list. This is
% not considered idiomatic Haskell code.
% 
% Instead, the code pattern in the |upper| and |sum function| -- and as we will
% show further on, indeed in many recursive functions -- allow using higher-order
% functions to rewrite them to a more concise version. In this case, we can use
% |map| and |foldr|, which are defined as follows:
% 
% \begin{code}
% map :: (a -> b) -> [a] -> [b]
% map f []        = []
% map f (x : xs)  = f x : map f xs
% \end{code}

Instead of using explicit recursion again and again, the paramorphic 
pattern can be captured once and for all in a higher-order
function, the fold function. In case of list, the fold function
is also known as |foldr|.
\begin{code}
foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ z []        = z
foldr f z (x : xs)  = f x (foldr f z xs)
\end{code}

Any other paramorphism over lists can easily be expressed
as an invocation of |foldr|.

\begin{code}
upper' :: String -> String
upper' = foldr (\x xs -> toUpper x : xs) []

sum' :: [Int] -> Int
sum' = foldr (+) 0
\end{code}

% \noindent Let us briefly list the advantages these alternative versions exhibit.
% 
% \begin{itemize}
% 
% \item First, it is immediately clear to any functional programmer who has
% grasped the concepts of |map| and |foldr|, how these functions operate on their
% argument(s).
% 
% Once the higher-order function is understood in terms of performance,
% control flow, and other aspects, it is usually trivial to understand functions
% written in terms of this higher-order function. As such, the code can be grokked
% more swiftly and without suprises.
% 
% % TODO: Cite something on concise code can be read faster (some Scala study?)
% 
% \item Second, the code becomes much more concise. This results in less
% boilerplate, less code to read (and to debug). Since the number of bugs is
% usually proportional to the number of code lines \cite{gaffney1984}, this
% suggests there should be fewer bugs.
% 
% \item Third, famous higher-order functions exhibit well-known
% properties that allow them to be reasoned about. For example, for any |f| and
% |xs|:
% 
% \begin{spec}
% length (map f xs) == length xs
% \end{spec}
% 
% As such, these properties need only be proven once, independently of |f|. This
% approach saves quite some effort when reasoning about the program we are writing
% (or debugging).
% 
% In our example, we can immediately deduce that |upper'| does not change the
% length of its argument, because it is implemented in terms of |map|.
% 
% \item Finally, a number of well-known properties also allow for certain
% optimisations. Map fusion is a well-known example \cite{meijer1991}:
% 
% \begin{spec}
% map f . map g = map (f . g)
% \end{spec}
% 
% This optimisation merges two maps over a list, so that no temporary list needs
% to be created, and we only need to loop over a list once instead of twice.
% 
% \end{itemize}
% 
% Hence, it should be clear that manually rewriting functions using higher-order
% functions offers some nice advantages. In what follows, we will aim for
% automating this manual labour, further simplifying the programmer's task. In
% order to do so, we need some manner in which to detect recursion patterns in a
% (sufficiently) general way.


%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
\paragraph{Generalised foldr}

% As we mentioned in the introduction, one of our goals is to automatically detect
% instances of well-known recursion patterns.  Our work around the detection of
% recursion pattern revolves mostly around |foldr|. There are several reasons for
% this.
% 
% First, |foldr| is an \emph{elementary} higher-order function. Many other
% higher-order functions (such as |map|, |filter|, and |foldl|) can actually be
% redefined in terms of |foldr|.
% 
% \begin{code}
% map' :: (a -> b) -> [a] -> [b]
% map' f = foldr (\x xs -> f x : xs) []
% \end{code}
% 
% This means that every function which can be written as an application of |map|
% can also be written as an application of |foldr|.
% 
% This allows us to work in a bottom-up fashion, first detecting a |foldr|-like
% pattern before classifying the pattern as an instance of a more specific
% higher-order function such as |map|.

Paramorphisms and fold functions are of course not limited
to lists. They extend readily to other inductive algebraic datatypes.

% Applying |foldr| yields a
% \emph{catamorphism} \cite{meijer1991}; this is applicable to arbitrary algebraic
% data types instead of just Haskell lists.

Consider the following example of leaf trees.

\begin{code}
data Tree a
    = Leaf a
    | Branch (Tree a) (Tree a)
    deriving (Show)
\end{code}

\begin{code}
sumTree :: Tree Int -> Int
sumTree (Leaf x)      = x
sumTree (Branch l r)  = sumTree l + sumTree r
\end{code}

\noindent This allows us to illustrate a fold over a |Tree|:

\begin{code}
foldTree  ::  (a -> r)
          ->  (r -> r -> r)
          ->  Tree a
          ->  r
foldTree l _ (Leaf x)      = l x
foldTree l b (Branch x y)  =
    b (foldTree l b x) (foldTree l b y)
\end{code}

\begin{code}
sumTree' :: Tree Int -> Int
sumTree' = foldTree id (+)
\end{code}
In general, a fold function transforms an inductive datatype into a value of a
user-specified type |r| by replacing every constructor by a user-specified
function.

Note that the fold function for a datatype is unique up to isomorphism (e.g.,
swapping the order of arguments), and characterized by the universal property
of folds~\cite{hutton1999}.  In fact, the fold function for an inductive
datatype can be derived automatically from its definition. We have implemented
a Template Haskell~\cite{sheard2002} routine to do so. For example, the
above |foldTree| function can be automatically generated as follows. 

%{
%format Tree = "`Tree"
\begin{spec}
$(deriveFold Tree "foldTree")
\end{spec}
%}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Fusion}

One of the main advantages of expressing functions in terms of fold is that
they inherit known properties of fold, which can be used for reasoning or for
\emph{optimization}.  In this work, we look at one such optimization and first
explain it for lists before generalizing it to other inductive datatypes.

Haskell best practices encourage building complicated functions by composing
small, easy to understand functions, rather than writing complex functions in a
monolithic way. An example is the following sum-of-odd-squares function:
\begin{code}
sumOfSquaredOdds' :: [Int] -> Int
sumOfSquaredOdds' = sum . map (^ 2) . filter odd
\end{code}
This code is quite compact and easy to compose from existing library functions.
However, when compiled naively, it is also rather inefficient because it
performs three loops and allocates two intermediate lists ( one as a result of
|filter odd|, and another as result of |map (^ 2)|) that are immediately
consumed again.

With the help of fusion, |foldr|/|build| fusion in particular, the above code
can be automatically transformed into the much more efficient definition:
\begin{code}
sumOfSquaredOdds :: [Int] -> Int
sumOfSquaredOdds [] = 0
sumOfSquaredOdds (x : xs)
    | odd x      = x ^ 2 + sumOfSquaredOdds xs
    | otherwise  = sumOfSquaredOdds xs
\end{code}
which performs only a single loop and allocates no intermediate lists.


foldr/build fusion makes it possible to optimise this function by ensuring no
intermediate lists are created.

We already showed that |foldr cons nil| inspects the list over which we are
folding, and then chooses the function |cons| or |nil|, based on whether it
encounters the |:| or |[]| constructor, respectively. This function is then
applied on the subterms of the constructor.

Now, these constructors are determined by the function which builds the list.
For example, consider the function |replicate|. This function chooses the
constructor |:| |n| times and then chooses the constructor |[]|.

\begin{code}
replicate :: Int -> a -> [a]
replicate n x
    | n <= 0     = []
    | otherwise  = x : replicate (n - 1) x
\end{code}

Now, consider that we apply |foldr cons nil| to the list generated by
|replicate|. Intuitively, we wonder if |replicate| can somehow use |cons| and
|nil| directly, instead of using |:| and |[]|. This would effectively remove an
intermediate list which is first build by |replicate| and then consumed by
|foldr|.

In order to turn this intuition into practice, the |build| function is
introduces. This function allows us to abstract over constructors.

%{
%format . = "."
\begin{code}
build :: (forall b. (a -> b -> b) -> b -> b) -> [a]
build g = g (:) []
\end{code}
%}

Then, the fusion rule is given by:
\[ |foldr cons nil (build g)| ~~ |==| ~~ |g cons nil| \]

Let us look at the |replicate| example again. In order to use this optimisation,
|replicate| needs to be rewritten. Using |build|, we arrive at this alternative
version.

\begin{code}
replicate' :: Int -> a -> [a]
replicate' n x = build $ \cons nil ->
    let g n' x'
            | n' <= 0    = nil
            | otherwise  = cons x' (g (n' - 1) x')
    in g n x
\end{code}

Let us look what happens when we now try to simplify the following expression.

\begin{spec}
sum' (replicate' n x)
\end{spec}

We clearly consume a list (|sum|) after generating it (|replicate'|), so we
should be able to remove the intermediate list using foldr/build fusion.

\begin{spec}
    sum' (replicate' n x)

== {- inline |sum'| -}

    foldr (+) 0 (replicate' n x)

== {- inline |replicate'| -}

    foldr (+) 0 (build $ \cons nil ->
        let g n' x'
                | n' <= 0    = nil
                | otherwise  = cons x' (g (n' - 1) x')
        in g n x)

== {- foldr/build fusion -}

    (\cons nil ->
        let g n' x'
                | n' <= 0    = nil
                | otherwise  = cons x' (g (n' - 1) x')
        in g n x) (+) 0

== {- $\beta$-reduction -}

    let g n' x'
            | n' <= 0    = 0
            | otherwise  = x' + g (n' - 1) x'
    in g n x

\end{spec}

Altough arguable less readable, we can see that the final version of |sum'
(replicate' n x)| does not need to create a intermediate list. Our optimisation
is a success in this case.

We will now show how we can generalise the foldr/build rule to work on arbitrary
algebraic datatypes.

%{
%format . = "."
\begin{code}
buildTree  ::  (forall b. (a -> b) -> (b -> b -> b) -> b)
           ->  Tree a
buildTree g = g Leaf Branch
\end{code}
%}

Using the libraries we developed, the programmer does not have to write this
function manually. Instead, it can be automatically generated using Template
Haskell, just like the |foldTree| function.

%{
%format Tree = "`Tree"
\begin{spec}
$(deriveBuild Tree "buildTree")
\end{spec}
%}


% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% \subsection{foldr/foldr fusion}
% 
% TODO: Give a quick overview what foldr-foldr fusion is. Explain we don't
% implement it, but that our work facilitates the optimisation.

%-------------------------------------------------------------------------------
\subsection{Automation}

The main Haskell compiler, GHC, currently provides limited automation for
foldr/build fusion.

\tom{explain rewrite rule and limitation to List library with encapsulated
     build function}

Clearly, this existing automation is severely limited. Firstly, it is
restricted to lists and secondly it requires programmers to explicitly define
their functions in terms of |build| and |foldr|. The latter is further
compounded by the fact that |build| is a non-exported function of the
|Data.List| library.

This work lifts both limitations. It allows programmers to write their
functions in explicitly recursive style and performs foldr/build fusion for any
directly inductive datatype.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Identifying folds}
\label{subsection:identifying-folds}

\subsection{Core Expressions}
\label{section:core-expressions}

For simplicity, we only use a subset of Haskell called Core. This Core language
is not much more than System F extended with a |let| and |case| construct
\cite{sulzmann2007}. However, while it is a subset, it is important to note
every Haskell expression can be translated into a semantically equal Core
expression.

%{
%format (many (x)) = "\overline{" x "}"
\begin{spec}
program ::= many b

b ::= x = e

p ::= K (many (x))

e  ::=  x
   |    e e
   |    \x -> e
   |    literal
   |    let many b in e
   |    case e of many (p -> e)
\end{spec}
%}

A program consists of different top-level bindings, in which expressions are
bound to variables.

An expression in $\lambda$-calculus can be a variable, an application or a
lambda term. Core extends this expression type with literals, |let| and |case|
expressions.

|let| allows binding expressions to variables, so they only need to be evaluated
once. This way, the programmer has more control over the evaluation order,
something which is not defined for $\lambda$-calculus.

|case| is the only branching construct allowed and is used to evaluate and
inspect the constructor. For every branch, an expression is bound to a pattern.
This pattern consists of a constructor and can optionally bind a number of
subterms to variables.

In Table \ref{tabular:haskell-core}, we demonstrate how some common Haskell
expressions are translated into Core.

\begin{table}
\begin{center}
\begin{tabular}{l||l}
|e1 + e2|              & |(+ e1) e2|                           \\
|if c then e1 else e2| & |case c of True -> e1; False -> e2;|  \\
|f x y = e|            & |f = \x -> \y -> e|                   \\
|e1 where x = e2|      & |let x = e2 in e1|                    \\
|head (x : _) = x|     & |head = \l -> case l of (x : _) -> x| \\
\end{tabular}
\caption{Haskell expressions on the left, and the corresponding Core
expressions on the right}
\label{tabular:haskell-core}
\end{center}
\end{table}

In our actual implementation, we use the GHC Core language. We will come back to
this in more detail later, in subsection \ref{subsection:ghc-core}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Identifying folds}
\label{subsection:identifying-folds}

\begin{figure}[t]
\begin{center}
    \fbox{
        \begin{tabular}{c}

        % Bindings
        \AxiomC{|e| $\leadsto_f$ |e'|}
        \RightLabel{binds}
        \UnaryInfC{|f = e| $\leadsto$ |f = e'|}
        \DisplayProof
        \whiteline

        % Left-side arguments
        \AxiomC{|e| $\leadsto_{fx}$ |e'|}
        \RightLabel{left arguments}
        \UnaryInfC{|\x -> e| $\leadsto_f$ |\x -> e'|}
        \DisplayProof
        \whiteline

        % Right-side arguments
        \AxiomC{|\x -> e| $\leadsto_{|\x -> fxy|}$ |\x -> e'|}
        \RightLabel{right arguments}
        \UnaryInfC{|\x -> \y -> e| $\leadsto_{f}$ |\x -> y -> e'|}
        \DisplayProof
        \whiteline

        % Case
        \AxiomC{
            \begin{minipage}{0.4\columnwidth}
            \begin{spec}
            z, zs <- fresh
            e'2 = \z ->
                subst (subst e2 (f ys) zs) y z
            \end{spec}
            \end{minipage}
        }
        \AxiomC{
            \begin{minipage}{0.3\columnwidth}
            \begin{spec}
            x   `notElem` fv(e1)
            x   `notElem` fv(e'2)
            ys  `notElem` fv(e'2)
            \end{spec}
            \end{minipage}
        }
        \RightLabel{case}
        \BinaryInfC{
            \begin{minipage}{0.35\columnwidth}
            \begin{spec}
            \x -> case x of
                []        -> e1
                (y : ys)  -> e2
            \end{spec}
            \end{minipage}
            $\leadsto_f$ |\x -> foldr e'2 e1 x|
        }
        \DisplayProof

        \end{tabular}
    }
    % \addtocounter{figure}{-1} % Counter weird subfigure counter thingy
    \caption{Rewrite rules for introducing fold}
    \label{figure:fold-rules}
\end{center}
\end{figure}

In this section, we discuss the identification of folds that adhere to a certain
set of rules. We begin by explaining how these rules apply to folding over a
list. Generalising to arbitrary algebraic datatypes then follows naturally and
is discussed later on.

With our set of rules, we can rewrite explicit recursion as implicit recursion
using |foldr|. In these rules, the expression $x \leadsto y$ stands for
\emph{$x$ can be rewritten as $y$}.

The complete set of rules are shown in Figure \ref{figure:fold-rules}.

We now briefly discuss these rules and show how they can be applied in practice.
The simplest rule concerns bindings, which are of the form |f = e|. If the body
can be rewritten as a fold, then the binding can be rewritten in the same
fashion. Note that this rule applies to top-level bindings as well as to local
bindings, i.e., in |let| expressions.

A fold may have an arbitrary number of arguments. For example, consider the
following function:

\begin{code}
mapAppend :: (a -> b) -> [a] -> b -> [b]
mapAppend f [] z        = [z]
mapAppend f (x : xs) z  = f x : mapAppend f xs z
\end{code}

Here, we fold over a list with two extra arguments, namely |f| and |z|. For our
technique to work correctly, it is paramount that these arguments do not change
during recursive applications.

\textbf{TODO: Why?}

In the case of extra aguments being present, we rely on two separate deduction
rules -- for arguments on the left and on the right of the argument over which
we will perform the fold.

Finally, the bottom deduction rule from Figure \ref{figure:fold-rules} forms the
core of our fold recognition. It is more involved than the other rules and it
actually is trivially extended to arbitrary algebraic datatypes. To explain its
operation, we consider only the simplified version specific for lists.

An argument |x| is \emph{destroyed}, and we have an expression for every
constructor -- in this case |:| and |[]|. Naturally, the expression
corresponding to the |[]| constructor becomes the second argument to |foldr|.

For |:|, on the other hand, we have an expression |e2| which can use the
subterms |y|, |ys| bound by the |case| expression. In the rewritten version
using |foldr|, however, |y| and |ys| are not in scope. Hence, |e2| needs to be
converted to an anonymous function taking two parameters instead. Additionally,
the explicit recursion needs to be eliminated. This results in the corresponding
and rewritten expression |e'2|.

Let's look at a concrete example: where we have an expression for sum.

\begin{spec}
sum = \ls -> case ls of
    []        -> 0
    (x : xs)  -> x + sum xs
\end{spec}

We can apply our rules step-by-step to obtain the our result:

\begin{spec}
sum = \ls -> foldr (\z -> \zs -> z + zs) 0 ls
\end{spec}

% TODO: Examples for this last rule, alternative rule for arguments

% TODO: Check that stuff is in scope.

% TODO: Try to explain the theorem: f is a fold <-> the args are well-scoped.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Degenerate folds}
\label{subsection:degenerate-folds}

The algorithm described in \ref{subsection:identifying-folds} also classifies
\emph{degenerate folds} as being folds. |head| is an example of such a
degenerate fold:

\begin{code}
head :: [a] -> a
head (x : _)  = x
head []       = error "empty list"
\end{code}

Can be written as a fold:

\begin{code}
head' :: [a] -> a
head' = foldr const (error "empty list")
\end{code}

Fortunately we can easily detect these degenerate folds: iff no recursive
applications are made in any branch, we have a degenerate fold.

These degenerate folds are of no interest to us, since our applications focus on
optimisations regarding loop fusion. In degenerate folds, no such loop is
present, and hence the optimisation is futile.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Identifying build}

\begin{figure}[t]
\begin{center}
    % \begin{subfigure}{\columnwidth}
    \fbox{
    \begin{tabular}{cc}
        \multicolumn{2}{c}{
            \infer{
                |f a1 a2 ... = e|
                \rightharpoonup
                \begin{minipage}{0.5\columnwidth}
                \begin{spec}
                f a'1 a'2 ... = build $
                    \cons nil ->
                        let g a1 a2 ... = e'
                        in g a'1 a'2 ...
                \end{spec}
                \end{minipage}
            }{
                |cons, nil, g <- fresh|
                &
                |e| \rightharpoonup_{f, g, cons, nil} |e'|
            }
        }
        \\
        \infer{
            |f a1 a2 ...| \rightharpoonup_{f, g, cons, nil} |g a1 a2 ...|
        }{}
        &
        \infer{
            |[]| \rightharpoonup_{f, g, cons, nil} |nil|
        }{}
        \vspace{0.1in}
        \\
        \multicolumn{2}{c}{
            \infer{
                |(x : e)| \rightharpoonup_{f, g, cons, nil} |cons x e'|
            }{
                |e| \rightharpoonup_{f, g, cons, nil} |e'|
            }
        }
        \vspace{0.1in}
        \\
        \multicolumn{2}{c}{
            \infer{
                |let b = x in e| \rightharpoonup_{f, g, cons, nil}
                |let b = x in e'|
            }{
                |e| \rightharpoonup_{f, g, cons, nil} |e'|
            }
        }
        \vspace{0.1in}
        \\
        \multicolumn{2}{c}{
            \infer{
                \begin{minipage}{0.3\columnwidth}
                \begin{spec}
                \x -> case x of
                    c1 -> e1
                    c2 -> e2
                    ...
                \end{spec}
                \end{minipage}
                \rightharpoonup_{f, g, c, n}
                \begin{minipage}{0.3\columnwidth}
                \begin{spec}
                \x -> case x of
                    c1 -> e'1
                    c2 -> e'2
                    ...
                \end{spec}
                \end{minipage}
            }{
                \forall i. e_i \rightharpoonup_{f, g, c, n} e'_i
            }
        }
        \\
    \end{tabular}
    }
    % \end{subfigure}
    % \addtocounter{figure}{-1} % Counter weird subfigure counter thingy
    \caption{Deduction rules for identifying builds}
    \label{figure:build-rules}
\end{center}
\end{figure}

While foldr/build fusion is implemented in GHC, the |build| function is not
exported from the |Data.List| module, because it's rank-2 type is not
implementable in Haskell 98.

This means the developer is prevented from using |build| in its programs.
Additionally, even if the |build| function was available everywhere, an
inexperienced developer might not think of using this function.

This means there is a need to detect instances |build| automatically and rewrite
them automatically, as we already do for instances of folds. We use a similar
set of deduction rules for this.

Note that we use the simplified syntax |f a1 a2 ... = e| for |f = \a1 -> \a2 ->
... -> e|. This simplifies the set of rules, making them easier to understand.

We have a main deduction rule which replaces the body of a binding by a call to
|build|. A local function |g| is created, which is the worker of the function.

This is not strictly necessary for non-recursive functions, but having a single
rule is an implementation advantage.

We examine the body of the expression. We're allowed to look through |let| and
|case| expressions. If we find an application (|e arg|), we can rewrite |e| by
replacing:

\begin{itemize}
\item Recursive applications of |f| by |g|
\item |[]| by |nil|
\item |(:)| by |cons|
\end{itemize}

In the last case, we also need to check the second subterm of |(:)|, as another
constructor might appear there. For example, this is the case for:

\begin{code}
twice :: [a] -> [a]
twice []        = []
twice (x : xs)  = x : x : twice xs
\end{code}

We are very conservative, since correctness is of uttermost importance. Hence,
we don't allow arbitrary functions such as:

\ignore{
\begin{code}
foo = twice'
\end{code}
}

\begin{code}
twice' :: [a] -> [a]
twice' []        = []
twice' (x : xs)  = x : x : foo xs
\end{code}

Because |foo| might be referring literally to the [] and (:) constructors, and
since |foo| is possibly defined in another module, we have no way to know or
rewrite this.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Implementation and evaluation}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{The GHC Core language}
\label{subsection:ghc-core}

We already gave a brief, high-level explanation of the Core language in section
\ref{section:core-expressions}. In the next few sections, we explain how we
obtain and manipulate this language in practice.

GHC \cite{ghc} is the de-facto compiler for Haskell, altough some alternatives
exist. We selected GHC as target for our implementation because of this reason.

By choosing GHC, we have two convenient representations of Haskell code at our
disposal for analsis.

The most straightforward representation is the Haskell source code itself.
There are numerous parsing libraries to make this task easier
\cite{haskell-src-exts}.

However, during compilation, the Haskell code is transformed to the GHC Core
\cite{tolmach2009} language in a number of passes.

The latter is particulary interesting for our purposes. It offers the following
advantages over regular Haskell source code:

\begin{itemize}

\item First, GHC Core is a much less complicated language than Haskell, because
all syntactic features have been stripped away. As an illustration, the |Expr|
type used by \emph{haskell-src-exts} has 46 different constructors, while the
|Expr| type used by GHC Core only has 10!

\item Second, the GHC Core goes through multiple passes. Many of the passes
simplify the expressions in the source code, which in turns facilitates our
analysis. Consider the following example.

\begin{code}
jibble :: [Int] -> Int
jibble []        = 1
jibble (x : xs)  = wiggle x xs

wiggle :: Int -> [Int] -> Int
wiggle x xs = x * jibble xs + 1
\end{code}

Here, it is quite infeasible to recognise a foldr pattern prior to the inlining
of wiggle. However, once wiggle is inlined, it becomes quite clear that this is
a perfect match for our detector.

\item Finally, GHC Core is fully typed. This means we have access to type
information everywhere, which we can use in the analysis. While this is not
essential to our detector, it allows greater performance. Consider the simple
function add:

\begin{code}
add :: Int -> Int -> Int
add x y = x + y
\end{code}

Since no fold function will be associated to the |Int| datatype, we can
immediately skip analysing this function.

\end{itemize}

However, we must note that there is a major drawback to analyzing GHC Core
instead of Haskell code: it becomes much harder to use the results for
refactoring: in order to do refactoring, we would need an \emph{annotated}
expression type so the Core expressions can be traced back to the original
Haskell code. When we rewrite the Core expressions, the Haskell code must be
updated accordingly. This falls outside of the scope of this work.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{The GHC Plugins system}
\label{subsection:ghc-plugins}

In GHC 7.2.1, a new mechanism to manipulate and inspect GHC Core was introduced
\cite{ghc-plugins}. After careful consideration, we adopted this approach
because it turned out to be much more accessible compared to directly using the
GHC API.

To be more precise, most Haskell libraries and applications today use the Cabal
build system \cite{cabal}. If we want to examine such a package for folds, it is
simply a matter of patching the Cabal file to include our plugin.

Using this mechanism, our plugin can manipulate expressions, in the form of an
algebraic datatype, directly. We show a simplified expresssion type here:

\ignore{
\begin{code}
data Id = Id
data Literal = Literal
data AltCon = AltCon
\end{code}
}

\begin{code}
data Expr
    = Var Id
    | Lit Literal
    | App Expr Expr
    | Lam Id Expr
    | Let Bind Expr
    | Case Expr Id [Alt]

data Bind
    = NonRec Id Expr
    | Rec [(Id, Expr)]

type Alt = (AltCon, [Id], Expr)
\end{code}

|Id| is the type used for different kinds of identifiers. The |Id|s used in this
phase of the compilation are guaranteed to be unique. This means we don not have
to take scoping into account for many transformations. |Lit| is any kind of
literal. |App| and |Lam| are well-known from the $\lambda$-calculus and
represent function application and lambda abstraction respectively. |Let| is
used to introduce new recursive or non-recursive binds, and |Case| is used for
pattern matching -- the only kind of branching possible in GHC Core.


%-------------------------------------------------------------------------------
\subsection{Identifying folds}
\label{subsection:identifying-folds}

A first aspect we can evaluate is how well our detection of folds works.
Unfortunately, manually identifying folds in projects takes too much time. This
explains why it is especially hard to detect false negatives.

Additionally, very little other related work is done. The \emph{hlint}
\cite{hlint} tool is able to recognize folds as well, but its focus lies on
refactoring rather than optimisations.

In Table \ref{tabular:project-results}, we can see the results of running our
tool on some well-known Haskell projects. We classify folds into three
categories:

\begin{itemize}
\item Degenerate folds, as described in \ref{subsection:degenerate-folds};
\item List folds, folds over data structures of type |[a]|;
\item Data folds, folds over any other data structure.
\end{itemize}

\begin{table}
\begin{center}
\ra{1.3}
\begin{tabular}{@@{}lrrr@@{}}
\toprule
                    & Degenerate & List & Data& hlint \\
\midrule
\textbf{hlint}      &   248             & 17   & 25  & 0     \\
\textbf{parsec}     &   150             &  6   &  0  & 0     \\
\textbf{containers} &   311             &  7   & 75  & 0     \\
\textbf{pandoc}     & 1,012             & 35   &  1  & 0     \\
\textbf{cabal}      & 1,701             & 43   & 30  & 1     \\
\bottomrule
\end{tabular}
\caption{Results of identifying folds in some well-known projects}
\label{tabular:project-results}
\end{center}
\end{table}

We also tested our tool on the test cases included in the hlint source code, and
we identified the same folds. However, in arbitrary code (See Table
\ref{tabular:project-results}), our tool detects more possible folds than hlint.
This suggests that we detect a strict superset of possible folds, even for
lists. The fact that the number of possible folds in these projects found by
hlint is so low indicates that the authors of the respective packages might have
used hlint during development.

%-------------------------------------------------------------------------------
\subsection{Identifying builds}

%-------------------------------------------------------------------------------
\subsection{Optimization results}

\tom{We need to specifically address what happens to functions that are both
     a fold and a build like |map| and |filter|.}

\tom{We need to benchmark foldr/build examples from the literature.}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Related work}

In ``A short cut to deforestation'' \cite{gill1993}, the foldr/build rule is
discussed. The authors discuss the benefits of this approach, supported by many
benchmarks. However, they also mention the issues with the fact that every
programmer needs to use a specific style (i.e., write all functions in terms of
|foldr|/|build|). Naturally, this is exactly what our research mitigates!

Stream fusion \cite{coutts2007} is an advanced alternative to foldr/build
fusion. It has the benefits of easily being able to fuse zips and left folds.
However, at the time of writing, there is no known reliable method of optimising
uses of |concatMap|. |concatMap| is important because it represents the entire
class of nested list computations, including list comprehensions
\cite{coutts2010}.

The \emph{hlint} \cite{hlint} tool is also able to recognise several
higher-order functions, under which |foldr|. However, as we already showed in
\ref{subsection:identifying-folds}, we are able to detect more instances of
folds for Haskell lists. Additionally, detecting fold instances for arbitrary
algebraic datatypes is outside of the scope of hlint.

\begin{itemize}
\item fold applications
\item supercompilation
\item datatypes a la carte
\item attribute grammars
\end{itemize}


%===============================================================================
\section{Conclusion}

\tom{mention mutually recursive ADTs as important future work}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% \appendix
% \section{Appendix Title}
% 
% This is the text of the appendix, if you need one.
% 
% \acks
% 
% Acknowledgments, if needed.

% References
\bibliographystyle{abbrvnat}
\bibliography{references}

\end{document}

\documentclass[preprint]{sigplanconf}

%include polycode.fmt

\usepackage{amsmath}
\usepackage[numbers]{natbib}  % For URLs in bibliography

% Used to hide Haskell code from LaTeX
\long\def\ignore#1{}

% For typesetting infer rules, found in proof.sty in this directory
\usepackage{proof}

% Document metadata

\conferenceinfo{WXYZ '05}{date, City.}
\copyrightyear{2005}
\copyrightdata{[to be supplied]}

\titlebanner{banner above paper title}        % These are ignored unless
\preprintfooter{short description of paper}   % 'preprint' option specified.

\title{Automatic detection of recursion patterns}
\subtitle{Subtitle Text, if any}

\authorinfo{Name1}{Affiliation1}{Email1}
\authorinfo{Name2\and Name3}{Affiliation2/3}{Email2/3}

\begin{document}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\maketitle

\ignore{
\begin{code}
import Data.Char     (toUpper)
import Prelude       hiding (head, foldr, map, sum)
\end{code}
}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\begin{abstract}
Rewriting explicitly recursive functions in terms of higher-order functions such
as |fold| and |map| brings many advantages such as conciseness, improved
readability, and it facilitates some optimizations. However, it is not always
straightforward for a programmer to write functions in this style. We present an
approach to automatically detect these higher-order functions, so the programmer
can have his cake and eat it, too.
\end{abstract}

% TODO: Explicit results, evaluation

\category{CR-number}{subcategory}{third-level}

\terms
term1, term2

\keywords
keyword1, keyword2


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Introduction}

% TODO: 2 paragraphs, 1 about own research/additions


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Motivation}

In early programming languages, developers manipulated the control flow of their
applications using the \texttt{goto} construct. This allowed \emph{arbitrary}
jumps through code, which brought with many disadvantages \cite{dijkstra1968}.
In particular, it could be very hard to understand code written in this style.

Later programming languages favored use of control stuctures such as
\texttt{for} and \texttt{while} over \texttt{goto}. This made it easier for
programmers and tools to analyze these structures, e.g. on pre- and
postconditions.

A similar argument can be made about \emph{arbitrary recursion} in functional
programming languages. Consider the functions:

\begin{code}
upper :: String -> String
upper []        = []
upper (x : xs)  = toUpper x : upper xs
\end{code}

\begin{code}
sum :: [Int] -> Int
sum []        = 0
sum (x : xs)  = x + sum xs
\end{code}

These functions can be rewritten using the \emph{higher-order} functions |map|
and |foldr|.

\begin{code}
map :: (a -> b) -> [a] -> [b]
map f []        = []
map f (x : xs)  = f x : map f xs
\end{code}

\begin{code}
foldr :: (a -> b -> b) -> b -> [a] -> b
foldr _ z []        = z
foldr f z (x : xs)  = f x (foldr f z xs)
\end{code}

Which yields the more concise versions:

\begin{code}
upper' :: String -> String
upper' = map toUpper
\end{code}

\begin{code}
sum' :: [Int] -> Int
sum' = foldr (+) 0
\end{code}

The rewritten versions have a number of advantages.

\begin{itemize}
\item An experienced programmer will be able to read and understand the latter
versions much quicker: he or she immediately understands how the recursion works
by recognizing the higher-order function.

% TODO: Cite something on concise code can be read faster (some Scala study?)

\item The code becomes much more concise, which means there is less code to read
(and debug).

\item Interesting properties exist about these higher-order functions, e.g.:

\begin{spec}
length (filter f xs) <= length xs
\end{spec}

We can prove these properties once for an arbitrary |f|. Working like this saves
us a lot of work, since we then know applications of these higher-order
functions also adhere to these properties.

\item Last but not least, these properties allow for certain optimizations. Map
fusion is a well-known example \cite{meijer1991}:

\begin{spec}
map f . map g = map (f . g)
\end{spec}
\end{itemize}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Implementation}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Generalized foldr}

Our work around the detection of recursion pattern revolves mostly around
|foldr|. There are several reasons for this. First off, many other higher-order
functions (such as |map|, |filter|, and |foldl|) can be written in terms of
|foldr|.

\begin{code}
map' :: (a -> b) -> [a] -> [b]
map' f = foldr (\x xs -> f x : xs) []
\end{code}

If we work this way, we can first detect instances of |foldr| and then
optionally classify them as being instances of other higher-order functions such
as |map|.

Another advantage of focussing on |foldr| is that we can apply our work to more
than just recursion over lists. An application of |foldr| is a
\emph{catamorphism} \cite{meijer1991} --- and we can have those for arbitrary
algebraic data types instead of just lists.

Consider a fold over a tree:

\begin{code}
data Tree a
    = Leaf a
    | Branch (Tree a) (Tree a)
\end{code}

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
sumTree :: Tree Int -> Int
sumTree = foldTree id (+)
\end{code}

A general fold takes a number of functions as arguments, to be more precise,
exactly one function for every constructor of the datatype. If we consider the
product of these functions as operators in an \emph{algebra}, applying a
catamorphism is simply interpreting the data structure in terms of an algebra.

% TODO: Talk about subterms.

This indicates the concept of a fold is a very general idea, which is an
important motivation: our work will apply to any algebraic datatype rather than
just lists.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{GHC Core}
\label{subsection:ghc-core}

There are two convenient representations of Haskell code which we can analyze.

A first option is to analyze the Haskell code directly. Numerous parsing
libraries exist to make this task easier \cite{haskell-src-exts}.

During compilation, the Haskell code is translated throughout a different number
of passes. One particulary interesting representation is GHC Core
\cite{tolmach2009}.

Analyzing GHC Core for folds gives us many advantages:

\begin{itemize}
\item GHC Core is much less complicated, because all syntactic features have
been stripped away.

\item The GHC Core goes through multiple passes. This is very useful since we
can rely on other passes to help our analysis. For example, it might be
impossible to recognize certain folds before a certain function is inlined.

\item We have access to type information, which we can use in the analysis.
\end{itemize}

However, we must note that there is a major drawback to analyzing GHC Core
instead of Haskell code: it becomes much harder (and outside the scope of this
project) to use the results for refactoring.

In GHC 7.2.1, a new mechanism to manipulate and inspect GHC Core was introduced
\cite{ghc-plugins}. We decided to use this system since it is much more
accessible than using the GHC API directly, especially when Cabal is used as
well.

This plugins mechanism allows us to manipulate expressions directly. We show a
simplified expresssion type here:

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
phase of compilation are guaranteed to be unique, which means we don't have to
take scoping into account for many transformations. |Lit| is any kind of
literal. |App| and |Lam| are well-known from the $\lambda$-calculus. |Let| is
used to introduce new recursive or non-recursive binds, and |Case| is used for
pattern matching---the only kind of branching possible in GHC Core.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Identifying folds}
\label{subsection:identifying-folds}

% TODO: Try to describe our algorithm with a pattern/BNF + predicates

The trick in $fold$ is that we create an anonymous function which will allow us
to replace a specific argument with a subterm later.

\begin{spec}
<fold f>
    ::= <fold' f f>
\end{spec}

\begin{spec}
<fold' f f>
    ::= Lam x <foldOver (\y -> App f y) x>
      | Lam x <fold' (App f x) f>
\end{spec}

\begin{spec}
<foldOver f x>
    ::= Lam y <foldOver f x>
      | Case x of <alts f x>
\end{spec}

\begin{spec}
<alts f x>
    ::= <alt f x>
      | <alts f x>; <alt f x>
\end{spec}

\begin{spec}
<alt f x>
    ::= Constructor <subterms> <body>
\end{spec}

Since a fold applies an algebra to a datatype, we must have an operator from
this algebra for each constructor. We can retrieve this operator be writing it
as anonymous function based on |<body>|.

Our function $rewrite$ works on these $<alt>$ constructs by turning the body
into an anonymous function, step by step, by adding an argument for each
subterm.

If the subterm is recursive we expect a recursive call to $f$, otherwise we
treat the subterm as-is.

%format t1 = "t_1"
%format subst (term) (v) (e) = "\mathopen{}" term "[^{" v "}_{" e "}\mathclose{}"

\begin{spec}
rewrite f []        body  = body
rewrite f (t1 : ts) body
    | isRecursive t1      = Lam x (subst ((rewrite f ts body)) ((f t1)) x)
    | otherwise           = Lam x (subst ((rewrite f ts body)) t1 x)
\end{spec}

With the first argument to $Lam$, $x$, a fresh variable. Let's look at an
example.

\begin{spec}
sum :: [Int] -> Int
sum = \ad -> case ad of
    []        -> 0
    (x : xs)  -> x + sum xs
\end{spec}

If we rewrite the $:$ constructor in the $sum$ function, we get:

%format sub (x) = "\mathopen{}t_{" x "}\mathclose{}"
%format beta = "\beta"

\begin{spec}
rewrite (\t -> sum t) [sub x, sub xs] (sub x + sum (sub xs))
    = <definition rewrite>
        \x -> rewrite (\t -> sum t) [sub xs] (subst ((sub x + sum (sub xs))) (sub x) x)
    = <substitution>
        \x -> rewrite (\t -> sum t) [sub xs] (x + sum (sub xs))
    = <definition rewrite>
        \x y -> rewrite (\t -> sum t) [] (subst ((x + sum (sub xs))) ((\t -> sum t) (sub xs)) y)
    = <beta reduction>
        \x y -> rewrite (\t -> sum t) [] (subst ((x + sum (sub xs))) (sum (sub xs)) y)
    = <substitution>
        \x y -> rewrite (\t -> sum t) [] (x + y)
    = <definition rewrite>
        \x y -> x + y
\end{spec}

While this is a simple example, this also works in the more general case.

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
optimizations regarding loop fusion. In degenerate folds, no such loop is
present, and hence the optimization is futile.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Application: fold-fold fusion}

As we discussed in \ref{subsection:ghc-core}, the fact that we are working on
the level of GHC Core makes it hard to use our rewrite results for refactoring.
However, we can look at some interesting optimizations.

\emph{Fold-fold fusion} is a technique which fuses two folds over the same data
structure into a single fold. This allows us to loop over the structure only
once instead of twice.

\begin{code}
mean :: [Int] -> Double
mean xs = fromIntegral (sum xs) / fromIntegral (length xs)
\end{code}

If we know from previous analysis results that |sum| is a fold with arguments
|((+), 0)| and |len| is a fold with arguments |(const (+ 1), 0)|, we can apply
fold-fold fusion here:

% TODO: Describe the more generic pattern. Include definition of (***).

\begin{code}
mean' :: [Int] -> Double
mean' xs =
    fromIntegral sum' / fromIntegral len'
  where
    (sum', len') = foldr (\x -> (+ x) *** (+ 1)) (0, 0) xs
\end{code}

We see that for lists, this optimization maps to the arrow operation |***|:

\begin{code}
(***) :: (a -> b) -> (c -> d) -> (a, c) -> (b, d)
(***) f g (x, y) = (f x, g y)
\end{code}

%format Xc = "\mathopen{} X_c \mathclose{}"
%format Yc = "\mathopen{} Y_c \mathclose{}"

In the more general case, we have two folds over the same value. Say that we
fold once with algebra |X| and once with algebra |Y|. Our final algebra is the
product |(X, Y)|. Since each constructor |c| has an associated operator in |Xc|
and |Yc|, we can create a combined operator |(Xc, Yc)| for each constructor.

This shows that we can apply fold-fold fusion to arbitrary datatypes and not
just lists. Additionally, we can repeatedly apply this optimization to fuse an
arbitrary amount of $n$ folds into a single fold with an $n$-tuple.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{When can we apply fold fusion?}

Strictly spoken, we can always apply fold fusion, because of Haskell's laziness.
However, if two folds appear in different branches of a case expression, we will
often not have an actual optimization. Let's look at a simple counterexample:

\begin{code}
value :: [Int] -> Int
value xs
    | length xs < 3  = 0
    | otherwise      = sum xs
\end{code}

Suppose that we choose the |length xs < 3| branch in most cases. The |length|
and |sum| folds can be fused into a single fold, and the thunk created for the
result of |sum xs| will never be evaluated. However, there is still some
overhead associated with creating thunks, which is why fold-fold fusion is not
in all cases an optimization.

Hence, instead of always applying fold-fold fusion, we choose to only apply the
transformation where two fusable folds appear in the same \emph{branch} of an
expression.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Detecting fold fusion}

% TODO: Can we describe this using the same pattern syntax?

% TODO: We can actually always apply this because of laziness. However, it's not
% always an optimization. We must be more precise in our description.

% TODO: Don't talk about Let, Lam constructs, talk about expressions.

\begin{spec}
<fusable>
    ::= Let <fusable> <fusable>
    ::= Lam <fusable> <fusable>
    ::= App fold <args>
    ::= App <fusable> <fusable>
\end{spec}

This algorithm works as follows: we first find an application of a function we
previously idenfitied as fold. We store a reference to the data structure $x$
which is folded over.

Then, we search the expression tree for other expressions in which we apply a
function to $x$. However, our search scope is limited: we do not inspect the
different branches if we encounter a |case| expression.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Evaluation}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Identifying folds}

A first aspect we can evaluate is how well our detection of folds works.
Unfortunately, manually identifying folds in projects takes too much time. This
explains why it is especially hard to detect false negatives.

Additionally, very little other related work is done. The \emph{hlint}
\cite{hlint} tool is able to recognize folds as well, but its focus lies on
refactoring rather than optimizations.

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
\begin{tabular}{l||rrr||r}
                    & Degenerate folds & List & Data& hlint \\
\hline
\textbf{hlint}      &  248             & 17   & 25  & 0     \\
\textbf{parsec}     &  150             &  6   &  0  & 0     \\
\textbf{containers} &  311             &  7   & 75  & 0     \\
\textbf{pandoc}     & 1012             & 35   &  1  & 0     \\
\textbf{cabal}      & 1701             & 43   & 30  & 1     \\
\end{tabular}
\label{tabular:project-results}
\caption{Results of identifying folds in some well-known projects}
\end{center}
\end{table}

We also tested our tool on the test cases included in the hlint source code, and
we identified the same folds. However, in arbitrary code (See Table
\ref{tabular:project-results}), our tool detects more possible folds than hlint.
This suggests that we detect a strict superset of possible folds, even for
lists. The fact that the number of possible folds in these projects found by
hlint is so low indicates that the authors of the respective packages might have
used hlint during development.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\subsection{Optimization results}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Related work}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\section{Conclusion}


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
\appendix
\section{Appendix Title}

This is the text of the appendix, if you need one.

\acks

Acknowledgments, if needed.

% References
\bibliographystyle{abbrvnat}
\bibliography{references}

\end{document}
